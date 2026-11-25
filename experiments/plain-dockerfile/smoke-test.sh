#!/usr/bin/env bash
# Smoke test for the :base dev container image content.
# Usage: docker run --rm -i IMAGE bash -s < smoke-test.sh
# Runs as the image's default user, offline.
# All checks run; the exit status is 1 if any failed. The version list at
# the end is meant for diffing two images.
set -o pipefail

failures=0

# Run one check quietly (stdin closed, since this script arrives on stdin).
check() {
    local name=$1
    shift
    if "$@" </dev/null >/dev/null 2>&1; then
        printf 'ok    %s\n' "${name}"
    else
        printf 'FAIL  %s\n' "${name}"
        failures=$((failures + 1))
    fi
}

# Small predicates used by the checks below.
has() { command -v "$1"; }
in_path() { case ":${PATH}:" in *":$1:"*) return 0 ;; *) return 1 ;; esac; }
in_group() { id -nG | tr ' ' '\n' | grep -qx "$1"; }
env_is() { [ "$(printenv "$1")" = "$2" ]; }
file_has() { grep -Fq -- "$2" "$1"; }
link_to() { [ -n "$1" ] && [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]; }
owned() {
    [ "$(stat -c %U "$1")" = "$2" ] && { [ -z "${3:-}" ] || [ "$(stat -c %G "$1")" = "$3" ]; }
}
# shellcheck disable=SC2016 # dpkg-query expands ${...} itself
pkg() { dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" | grep -q '^ii'; }
not() { ! "$@"; }
empty_dir() { [ -z "$(ls -A "$1" 2>/dev/null)" ]; }
plugin_installed() { grep -Rqs -- "$1" ~/.claude/settings.json ~/.claude/plugins; }

# --- user and environment ----------------------------------------------------
check "user vscode" [ "$(id -un)" = vscode ]
check "uid 1000" [ "$(id -u)" = 1000 ]
check "passwordless sudo" sudo -n true
check "HOME" [ "${HOME}" = /home/vscode ]
check "WORKDIR" [ "${PWD}" = /home/vscode ]
check "group nvm" in_group nvm
check "NVM_DIR" env_is NVM_DIR /usr/local/share/nvm
check "NVM_SYMLINK_CURRENT" env_is NVM_SYMLINK_CURRENT true
check "PYTHON_PATH" env_is PYTHON_PATH /usr/local/python/current
check "ENABLE_LSP_TOOL" env_is ENABLE_LSP_TOOL 1
check "no PIPX_HOME" test -z "${PIPX_HOME:-}"
for d in /usr/local/python/current/bin /usr/local/share/nvm/current/bin \
    /home/vscode/.local/bin; do
    check "PATH ${d}" in_path "${d}"
done

# --- Debian packages (Dockerfile.mcr-trixie list, Feature needs) -------------
for c in batcat bats eza fastfetch fdfind fzf delta just lazygit mc pass rg \
    shellcheck vim xh jq curl gpg sudo git gcc make; do
    check "command ${c}" has "${c}"
done
for p in bats-assert bats-file vim-doc vim-scripts libatomic1 python3 \
    python3-pip python3-venv; do
    check "package ${p}" pkg "${p}"
done
for p in pipx python3-dev python3-doc python3-tk; do
    check "no package ${p}" not pkg "${p}"
done

# --- home folders and uv -----------------------------------------------------
check "home .vscode-server/data/User" test -d ~/.vscode-server/data/User
check "machine-id empty" test ! -s /etc/machine-id
check "home herdr-core state mode 700" [ "$(stat -c %a ~/.local/state/herdr-core)" = 700 ]
check "home .ssh mode 700" [ "$(stat -c %a ~/.ssh)" = 700 ]
check "home .local owner" owned ~/.local vscode
check "home .cache owner" owned ~/.cache vscode
check "uv" test -x ~/.local/bin/uv
check "uvx" test -x ~/.local/bin/uvx
check "uv cache empty" empty_dir ~/.cache/uv
check "login PATH restore" test -x /etc/profile.d/00-restore-env.sh

# --- node, npm globals -------------------------------------------------------
check "node 24" sh -c 'node --version | grep -q "^v24\."'
for c in npm yarn corepack; do check "command ${c}" has "${c}"; done
check "nvm.sh" test -s /usr/local/share/nvm/nvm.sh
check "nvm current link" test -L /usr/local/share/nvm/current
check "NVM_DIR vscode:nvm" owned /usr/local/share/nvm vscode nvm
check "NVM_DIR setgid" test -g /usr/local/share/nvm
# shellcheck disable=SC2016 # literal text in the file
check "bash.bashrc nvm" file_has /etc/bash.bashrc '. "$NVM_DIR/nvm.sh"'
check "zshrc nvm" file_has /etc/zsh/zshrc 'export NVM_DIR="/usr/local/share/nvm"'
check "no npm cache" empty_dir ~/.npm/_cacache
for c in eslint tsc pyright pyright-langserver typescript-language-server editorconfig; do
    check "npm global ${c}" has "${c}"
done

# --- python and uv tools -----------------------------------------------------
for c in python3 python pydoc3 pip pip3; do check "command ${c}" has "${c}"; done
for l in python3 python pydoc3 pydoc; do
    check "python current/bin/${l}" test -L "/usr/local/python/current/bin/${l}"
done
check "python venv" python3 -m venv --help
for t in flake8 autopep8 black yapf mypy pydocstyle pycodestyle bandit \
    pipenv virtualenv pytest pylint; do
    check "uv tool ${t}" test -x "${HOME}/.local/bin/${t}"
done

# --- standalone CLIs and their files -----------------------------------------
check "gh" has gh
check "copilot" test -x /usr/local/bin/copilot
check "claude" test -x ~/.local/bin/claude
check "claude plugin pyright-lsp" plugin_installed pyright-lsp@claude-plugins-official
check "claude plugin typescript-lsp" plugin_installed typescript-lsp@claude-plugins-official
check "specify" test -x ~/.local/bin/specify
check "otelcol-contrib" test -x /usr/local/bin/otelcol-contrib
check "otel config OTLP" file_has /etc/otelcol-contrib/config.yaml 'endpoint: localhost:4317'
check "otel config exporter" file_has /etc/otelcol-contrib/config.yaml 'azuremonitor:'
check "spf" test -x /usr/local/bin/spf
check "bat link to batcat" link_to /usr/local/bin/bat /usr/bin/batcat
check "superfile config" file_has ~/.config/superfile/config.toml 'auto_check_update = false'
check "superfile bat preview" file_has ~/.config/superfile/config.toml 'code_previewer = "bat"'
check "superfile partial config" file_has ~/.config/superfile/config.toml 'ignore_missing_fields = true'
check "superfile nerdfont off" file_has ~/.config/superfile/config.toml 'nerdfont = false'
check "herdr" test -x ~/.local/bin/herdr
check "herdr-core" test -x ~/.local/bin/herdr-core
check "hc is herdr-core" link_to "$(command -v hc)" ~/.local/bin/herdr-core
check "herdr bash completion" test -f /usr/share/bash-completion/completions/herdr
check "herdr zsh completion" test -f /usr/local/share/zsh/site-functions/_herdr
check "herdr config" file_has ~/.config/herdr/config.toml 'onboarding = false'
check "herdr version_check off" file_has ~/.config/herdr/config.toml 'version_check = false'
check "herdr manifest_check off" file_has ~/.config/herdr/config.toml 'manifest_check = false'
check "herdr-core skill claude" test -f ~/.claude/skills/herdr-core/SKILL.md
check "herdr-core skill copilot" test -f ~/.copilot/skills/herdr-core/SKILL.md
check "copilot lsp-config" file_has ~/.copilot/lsp-config.json pyright-langserver
check "claude LSP memory" test -f ~/.claude/CLAUDE.md

echo
if [ "${failures}" -gt 0 ]; then
    echo "RESULT: ${failures} check(s) failed"
else
    echo "RESULT: all checks passed"
fi

# --- version list for diffing two images -------------------------------------
# First output line of each command, then npm, uv, and dpkg inventories.
ver() {
    local name=$1
    shift
    printf '%s: %s\n' "${name}" "$("$@" </dev/null 2>&1 | head -n 1)"
}
echo
echo "=== versions"
ver debian cat /etc/debian_version
ver git git --version
ver node node --version
ver npm npm --version
ver python3 python3 --version
ver uv uv --version
ver gh gh --version
ver copilot copilot --version
ver claude claude --version
ver otelcol-contrib otelcol-contrib --version
ver spf spf --version
ver herdr herdr --version
ver herdr-core herdr-core --version
echo "PATH=${PATH}"
echo "=== /etc/profile.d/00-restore-env.sh"
cat /etc/profile.d/00-restore-env.sh
echo "=== npm globals"
# shellcheck disable=SC2016 # JavaScript template literal
npm ls -g --depth=0 --json </dev/null 2>/dev/null | node -e '
const d = JSON.parse(require("fs").readFileSync(0, "utf8"));
for (const [k, v] of Object.entries(d.dependencies || {})) console.log(`npm/${k}: ${v.version}`);
'
echo "=== uv tools"
uv tool list </dev/null 2>/dev/null | sed -nE 's|^([^- ][^ ]*) (v.*)$|uv/\1: \2|p'
echo "=== dpkg packages"
# shellcheck disable=SC2016 # dpkg-query expands ${...} itself
dpkg-query -W -f='dpkg/${Package}: ${Version}\n' | sort

[ "${failures}" -eq 0 ]
