#!/bin/bash
# Smoke test for the base-sandbox image. Runs INSIDE the container:
#   docker run --rm -v "$PWD/test/container:/test:ro" IMAGE bash /test/smoke.sh
# It is mounted rather than baked in, so the test code never ships in the image.
set -uo pipefail

pass=0
fail=0

ok() {
    printf '  ok   %s\n' "$1"
    pass=$((pass + 1))
}
no() {
    printf '  FAIL %s\n' "$1"
    fail=$((fail + 1))
}

# A tool is present when it resolves on PATH AND answers its version flag
# successfully. Checking the exit status matters: several of these binaries are
# downloaded tarballs, and a wrong-architecture build is on PATH and runs - it
# just fails. An earlier version of this helper ignored the status and reported
# 'ok' for a binary that printed an error.
have() {
    local name="$1" version_flag="${2:---version}" out status
    if ! command -v "${name}" > /dev/null 2>&1; then
        no "${name} is not on PATH"
        return 1
    fi
    out="$("${name}" "${version_flag}" 2>&1)"
    status=$?
    out="$(echo "${out}" | head -n1)"
    if [ "${status}" -ne 0 ]; then
        no "${name} ${version_flag} exited ${status}: ${out}"
        return 1
    fi
    ok "${name}: ${out}"
}

check() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then ok "${label}"; else no "${label}"; fi
}

refute() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then no "${label}"; else ok "${label}"; fi
}

echo "== identity =="
check "runs as the 'vscode' user" test "$(id -un)" = vscode
check "uid is 1000" test "$(id -u)" = 1000
check "HOME is /home/vscode" test "${HOME}" = /home/vscode
check "Debian trixie" grep -q 'VERSION_CODENAME=trixie' /etc/os-release

echo "== no privilege escalation =="
refute "no sudo binary on PATH" command -v sudo
refute "no /usr/bin/sudo" test -e /usr/bin/sudo
refute "no sudoers drop-in for vscode" test -e /etc/sudoers.d/vscode
refute "vscode is not in the sudo group" bash -c 'id -nG | tr " " "\n" | grep -qx sudo'
for d in /usr/local/bin /usr/local/node/bin /usr/local/share/base-sandbox /etc/ssh /etc/otelcol-contrib; do
    refute "cannot write ${d}" bash -c "touch '${d}/.wtest'"
done

echo "== no baked SSH host keys =="
refute "no /etc/ssh host private keys" bash -c 'ls /etc/ssh/ssh_host_*_key'
refute "no /etc/ssh host public keys" bash -c 'ls /etc/ssh/ssh_host_*_key.pub'
refute "no host keys in the user home" bash -c 'ls "${HOME}"/.ssh/host_keys/* 2>/dev/null'
check "sshd is installed" test -x /usr/sbin/sshd
check "sshd-init.sh is executable" test -x /usr/local/share/base-sandbox/sshd-init.sh
check "entrypoint.sh is executable" test -x /usr/local/share/base-sandbox/entrypoint.sh
check "harden-runtime.sh is executable" test -x /usr/local/share/base-sandbox/harden-runtime.sh

echo "== language runtimes =="
have node
check "node is major 24" bash -c '[ "$(node -p "process.versions.node.split(\".\")[0]")" = "24" ]'
have npm
have npx
have python3
check "python3 is the OS interpreter" test -x /usr/bin/python3
have pip3
have pipx
have uv

echo "== npm global prefix =="
check "user npm prefix is ~/.npm-global" bash -c '[ "$(npm config get prefix)" = "${HOME}/.npm-global" ]'
check "user can install npm packages without root" test -w "${HOME}/.npm-global"

echo "== CLI tools =="
have git
have gh
have copilot
have claude
have az
# spec-kit's CLI has no --version flag, so check it the way its own Feature
# tests do.
check "specify is on PATH" command -v specify
check "specify --help runs" specify --help
have otelcol-contrib --version
have spf
have superfile
have herdr
have jq
have rg
have fzf
have bat
have fd
have eza
have delta
have lazygit
have just
have shellcheck
have exiftool -ver
have bats

echo "== npm-provided tooling =="
have eslint
have tsc
have pyright
check "pyright-langserver is on PATH" command -v pyright-langserver
have typescript-language-server

echo "== deliberately absent =="
refute "pi-dev is not installed" command -v pi
refute "no sudo, again, under its full path" test -e /bin/sudo

echo "== no setuid or setgid binaries =="
refute "no setuid-root binaries" bash -c 'find / -xdev -perm -4000 -type f 2>/dev/null | grep .'
refute "no setgid binaries" bash -c 'find / -xdev -perm -2000 -type f 2>/dev/null | grep .'

echo "== agent configuration =="
check "copilot lsp-config.json" test -f "${HOME}/.copilot/lsp-config.json"
check "lsp-config names pyright" grep -q pyright-langserver "${HOME}/.copilot/lsp-config.json"
check "claude user memory" test -f "${HOME}/.claude/CLAUDE.md"
check "ENABLE_LSP_TOOL=1" test "${ENABLE_LSP_TOOL:-}" = 1
check "herdr config" test -f "${HOME}/.config/herdr/config.toml"
check "herdr onboarding disabled" grep -q 'onboarding = false' "${HOME}/.config/herdr/config.toml"
check "otel collector config" test -f /etc/otelcol-contrib/config.yaml
check "otel connection string is resolved at runtime, not baked in" \
    grep -q '${env:APPLICATIONINSIGHTS_CONNECTION_STRING}' /etc/otelcol-contrib/config.yaml
refute "no connection string literal in the config" \
    grep -qi 'InstrumentationKey=' /etc/otelcol-contrib/config.yaml
check "superfile config wires up the installed previewers" \
    grep -qx 'code_previewer = "bat"' "${HOME}/.config/superfile/config.toml"
refute "otel collector is not running" bash -c 'pgrep -x otelcol-contrib'

echo "== telemetry defaults =="
check "GH_TELEMETRY=false" test "${GH_TELEMETRY:-}" = false
check "DO_NOT_TRACK=true" test "${DO_NOT_TRACK:-}" = true
check "AZURE_CORE_COLLECT_TELEMETRY=0" test "${AZURE_CORE_COLLECT_TELEMETRY:-}" = 0
check "azure telemetry off in ~/.azure/config" grep -q 'collect_telemetry *= *false' "${HOME}/.azure/config"
check "claude telemetry disabled" test "${DISABLE_TELEMETRY:-}" = 1

echo "== shell hardening =="
check "harden-shell.sh exists" test -r /usr/local/share/base-sandbox/harden-shell.sh
check "sourced from /etc/profile.d" test -r /etc/profile.d/00-base-sandbox-harden.sh
check "sourced from the top of ~/.bashrc" bash -c 'head -n2 "${HOME}/.bashrc" | grep -q harden-shell.sh'
check "a login shell clears VSCODE_IPC_HOOK_CLI" bash -c \
    'VSCODE_IPC_HOOK_CLI=/tmp/x bash -lc "[ -z \"\${VSCODE_IPC_HOOK_CLI:-}\" ]"'
check "an interactive shell clears SSH_AUTH_SOCK" bash -c \
    'SSH_AUTH_SOCK=/tmp/x bash -ic "[ -z \"\${SSH_AUTH_SOCK:-}\" ]" 2>/dev/null'
# The shape a coding agent actually uses: neither login nor interactive, so it
# is covered by BASH_ENV alone.
check "a bare 'bash -c' clears VSCODE_IPC_HOOK_CLI" bash -c \
    'VSCODE_IPC_HOOK_CLI=/tmp/x bash -c "[ -z \"\${VSCODE_IPC_HOOK_CLI:-}\" ]"'
check "BASH_ENV points at the hardening script" bash -c \
    '[ "${BASH_ENV:-}" = /usr/local/share/base-sandbox/harden-shell.sh ]'

echo
printf '%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
