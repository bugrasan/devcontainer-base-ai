#!/bin/bash
# Node.js from the official nodejs.org tarball, into /usr/local/node.
#
# Not the 'node' Dev Container Feature and not NodeSource: base-sandbox builds
# from a plain Dockerfile, and a tarball keeps the toolchain in one removable
# directory with an upstream-signed checksum, without adding a third-party apt
# repository and key to the image.
set -euo pipefail
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

NODE_MAJOR="${1:?node major version required}"
PREFIX="/usr/local/node"

arch="$(arch_for node)"
sums="$(mktemp)"
tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}" "${sums}"' EXIT

# latest-v<major>.x/SHASUMS256.txt names the current release of that line and
# carries its checksum, so one fetch resolves the version AND verifies it.
download "https://nodejs.org/dist/latest-v${NODE_MAJOR}.x/SHASUMS256.txt" "${sums}"
# Anchored: upstream also ships variant tarballs (musl, older-glibc builds)
# whose names contain the same substring.
asset="$(awk -v a="^node-v[0-9.]+-linux-${arch}[.]tar[.]xz$" '$2 ~ a { print $2; exit }' "${sums}")"
[ -n "${asset}" ] || die "no linux-${arch} tarball in the Node.js ${NODE_MAJOR}.x checksums file."
version="$(echo "${asset}" | sed -E 's/^node-(v[0-9.]+)-.*/\1/')"

log "installing Node.js ${version} (linux/${arch}) to ${PREFIX}"
download "https://nodejs.org/dist/${version}/${asset}" "${tmpdir}/node.tar.xz"
verify_sha256 "${tmpdir}/node.tar.xz" "$(awk -v a="${asset}" '$2 == a { print $1; exit }' "${sums}")"

mkdir -p "${PREFIX}"
tar -xJf "${tmpdir}/node.tar.xz" -C "${PREFIX}" --strip-components=1
rm -rf "${PREFIX}/share/doc" "${PREFIX}/share/man" "${PREFIX}/CHANGELOG.md" "${PREFIX}/README.md"

# ${PREFIX}/bin is on PATH via the Dockerfile's ENV, which also covers every
# global package binary npm drops there later - a symlink per binary would not.
"${PREFIX}/bin/node" --version
"${PREFIX}/bin/npm" --version
log "Node.js ${version} installed"
