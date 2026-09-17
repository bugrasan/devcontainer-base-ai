#!/bin/bash
# Tools that belong to the unprivileged user: uv, and the two uv-managed CLIs
# (spec-kit's 'specify' and the Azure CLI).
#
# Runs as root and drops to the target user per command, because uv keeps its
# tool environments per user. The launchers are symlinked into /usr/local/bin
# so they resolve in every shell, login or not.
set -euo pipefail
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

TARGET_USER="${1:?target user required}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
USER_BIN="${TARGET_HOME}/.local/bin"

# --- uv ---------------------------------------------------------------------
# Python itself, pip and pipx come from the OS (apt); uv is the one Python tool
# Debian does not package, and both installers below need it.
log "installing uv"
as_user "${TARGET_USER}" "curl -LsSf https://astral.sh/uv/install.sh | sh"
as_user "${TARGET_USER}" "command -v uv >/dev/null" || die "uv is not on the user's PATH after install."

uv_bin_dir="$(as_user "${TARGET_USER}" "uv tool dir --bin" 2>/dev/null | tail -n1 || true)"
[ -n "${uv_bin_dir}" ] || uv_bin_dir="${USER_BIN}"

# \$PATH, not ${PATH}: it has to reach the inner login shell unexpanded so it
# expands there, against that shell's PATH rather than root's.
link_tool() {
    local name="${1:?tool name required}" path
    path="$(su - "${TARGET_USER}" -c "export PATH=\"${uv_bin_dir}:${USER_BIN}:\$PATH\"; command -v ${name}" 2>/dev/null | tail -n1 || true)"
    [ -n "${path}" ] || die "'${name}' was installed but could not be found on the user's PATH."
    [ "${path}" = "/usr/local/bin/${name}" ] || ln -sf "${path}" "/usr/local/bin/${name}"
}

# --- spec-kit ---------------------------------------------------------------
# spec-kit publishes git tags, not GitHub releases, so resolve the tag directly.
speckit_tag="$(resolve_latest_git_tag https://github.com/github/spec-kit.git)"
log "installing spec-kit ${speckit_tag} ('specify' CLI)"
as_user "${TARGET_USER}" "uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@${speckit_tag}"
link_tool specify

# --- Azure CLI --------------------------------------------------------------
# From PyPI via uv rather than the packages.microsoft.com apt repository, so
# the image gains no third-party apt source or signing key. If the OS Python is
# ever ahead of what azure-cli supports, fall back to a uv-managed interpreter
# instead of failing the build.
log "installing the Azure CLI"
as_user "${TARGET_USER}" "uv tool install azure-cli" ||
    {
        warn "'uv tool install azure-cli' failed on the OS Python - retrying on a uv-managed Python 3.12."
        as_user "${TARGET_USER}" "uv tool install --python 3.12 azure-cli"
    }
link_tool az

# Telemetry off by default. 'az config set' writes ~/.azure/config, which is
# what az reads at run time; AZURE_CORE_COLLECT_TELEMETRY in the environment
# covers the case where that file is replaced by a mount.
as_user "${TARGET_USER}" "az config set core.collect_telemetry=false --only-show-errors" ||
    warn "could not write the Azure CLI telemetry setting - AZURE_CORE_COLLECT_TELEMETRY still disables it."

# Build caches, not tools: uv keeps a shared wheel cache that is worth tens of
# MB in the layer and is never read again at run time.
as_user "${TARGET_USER}" "uv cache clean" || true
log "user tools installed"
