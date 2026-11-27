#!/bin/bash

# exit on error, also inside pipes (curl | gunzip)
set -eo pipefail

# The 'install.sh' entrypoint script is always executed as the root user.
# For more details, see https://containers.dev/implementors/features#user-env-var
TARGET_USER="${_REMOTE_USER:-root}"
TARGET_HOME="${_REMOTE_USER_HOME:-/root}"
# On PATH for all shells (Dockerfile.mcr-trixie ENV PATH).
BIN_DIR="${TARGET_HOME}/.local/bin"

# TODO(pin): pin versions and checksums later; for now every download
# tracks the latest release, refreshed by the weekly no-cache rebuild.
# releases/latest/download/<asset> URLs avoid GitHub API rate limits.

ARCH="$(dpkg --print-architecture)"
case "${ARCH}" in
    amd64) MARKSMAN_ARCH=x64; TAPLO_ARCH=x86_64 ;;
    arm64) MARKSMAN_ARCH=arm64; TAPLO_ARCH=aarch64 ;;
    *) echo "ERROR: unsupported architecture: ${ARCH}" >&2; exit 1 ;;
esac

# curl with retries on any error; -f fails the build on HTTP errors.
fetch() {
    curl -fsSL --retry 3 --retry-delay 2 --retry-all-errors "$@"
}

mkdir -p "${BIN_DIR}"

# marksman: Markdown language server, one static binary.
MARKSMAN_URL="https://github.com/artempyanykh/marksman/releases/latest/download"
fetch -o "${BIN_DIR}/marksman" "${MARKSMAN_URL}/marksman-linux-${MARKSMAN_ARCH}"

# taplo: TOML toolkit; the release binary includes 'taplo lsp stdio'.
TAPLO_URL="https://github.com/tamasfe/taplo/releases/latest/download"
fetch "${TAPLO_URL}/taplo-linux-${TAPLO_ARCH}.gz" | gunzip > "${BIN_DIR}/taplo"

chmod 755 "${BIN_DIR}/marksman" "${BIN_DIR}/taplo"

# --- Deferred servers: uncomment a block, then its row in lsp-config ------
# WORK_DIR="$(mktemp -d)"
# trap 'rm -rf "${WORK_DIR}"' EXIT

# jdtls (Java): needs Java 25+. Nightly snapshot; latest.txt names the
# newest tarball. Lives in ~/.local/share/jdtls, which jdtls writes to.
# Claude Code: also add jdtls-lsp@claude-plugins-official (devcontainer.json).
# apt-get update
# apt-get install -y --no-install-recommends openjdk-25-jdk-headless
# rm -rf /var/lib/apt/lists/*
# JDTLS_BASE="https://download.eclipse.org/jdtls/snapshots"
# JDTLS_TGZ="$(fetch "${JDTLS_BASE}/latest.txt" | tr -d '[:space:]')"
# fetch -o "${WORK_DIR}/${JDTLS_TGZ}" "${JDTLS_BASE}/${JDTLS_TGZ}"
# JDTLS_SHA="$(fetch "${JDTLS_BASE}/${JDTLS_TGZ}.sha256")"
# echo "${JDTLS_SHA}  ${WORK_DIR}/${JDTLS_TGZ}" | sha256sum -c -
# mkdir -p "${TARGET_HOME}/.local/share/jdtls"
# tar -xzf "${WORK_DIR}/${JDTLS_TGZ}" -C "${TARGET_HOME}/.local/share/jdtls"
# ln -sf "${TARGET_HOME}/.local/share/jdtls/bin/jdtls" "${BIN_DIR}/jdtls"
# chown -R "${TARGET_USER}:" "${TARGET_HOME}/.local/share/jdtls"

# terraform-ls: latest version from HashiCorp's checkpoint API, checked
# against the release's SHA256SUMS.
# TFLS_CHECK="https://checkpoint-api.hashicorp.com/v1/check/terraform-ls"
# TFLS_VERSION="$(fetch "${TFLS_CHECK}" | jq -r .current_version)"
# TFLS_BASE="https://releases.hashicorp.com/terraform-ls/${TFLS_VERSION}"
# TFLS_ZIP="terraform-ls_${TFLS_VERSION}_linux_${ARCH}.zip"
# fetch -o "${WORK_DIR}/${TFLS_ZIP}" "${TFLS_BASE}/${TFLS_ZIP}"
# fetch "${TFLS_BASE}/terraform-ls_${TFLS_VERSION}_SHA256SUMS" \
#     | grep " ${TFLS_ZIP}\$" | (cd "${WORK_DIR}" && sha256sum -c -)
# unzip -o -q "${WORK_DIR}/${TFLS_ZIP}" terraform-ls -d "${BIN_DIR}"

# LemMinx (XML): native binary from the vscode-xml release; its .sha256
# covers the unzipped binary, not the zip.
# LEMMINX_ARCH="$([ "${ARCH}" = amd64 ] && echo x86_64 || echo aarch_64)"
# LEMMINX="lemminx-linux-${LEMMINX_ARCH}"
# LEMMINX_BASE="https://github.com/redhat-developer/vscode-xml/releases"
# LEMMINX_BASE+="/latest/download"
# fetch -o "${WORK_DIR}/${LEMMINX}.zip" "${LEMMINX_BASE}/${LEMMINX}.zip"
# unzip -o -q "${WORK_DIR}/${LEMMINX}.zip" -d "${WORK_DIR}"
# fetch "${LEMMINX_BASE}/${LEMMINX}.sha256" \
#     | (cd "${WORK_DIR}" && sha256sum -c -)
# install -m 755 "${WORK_DIR}/${LEMMINX}" "${BIN_DIR}/lemminx"

# We ran as root: hand the binaries (and ~/.local/bin if we created it) to
# the remote user.
chown "${TARGET_USER}:" "${BIN_DIR}" "${BIN_DIR}"/*

echo 'Done!'
