#!/bin/bash
# GitHub Copilot CLI from its release tarball, into /usr/local/bin.
#
# Deliberately WITHOUT the copilot-cli Feature's /etc/devcontainer-copilot-cli/
# auto-update flag file: that file makes the Feature check for a new release on
# every container start, which the :base image then had to switch off again in
# postCreateCommand. No flag file, no per-start network call, and 'copilot'
# still refreshes to the latest release at every weekly image rebuild.
set -euo pipefail
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

arch="$(arch_for node)"
asset="copilot-linux-${arch}.tar.gz"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

tag="$(resolve_latest_tag github/copilot-cli)"
log "installing GitHub Copilot CLI ${tag} (linux/${arch})"
download "https://github.com/github/copilot-cli/releases/download/${tag}/${asset}" "${tmpdir}/${asset}"
verify_from_checksums_file "${tmpdir}/${asset}" "${asset}" \
    "https://github.com/github/copilot-cli/releases/download/${tag}/checksums.txt"

mkdir -p "${tmpdir}/extract"
tar -xzf "${tmpdir}/${asset}" -C "${tmpdir}/extract"
bin="$(find "${tmpdir}/extract" -type f -name copilot | head -n1)"
[ -n "${bin}" ] || die "no 'copilot' binary in ${asset}"
install -m 0755 "${bin}" /usr/local/bin/copilot
# Fail here rather than in CI if the download was for the wrong architecture.
/usr/local/bin/copilot --version > /dev/null || die "copilot was installed but does not run."
log "GitHub Copilot CLI installed"
