#!/usr/bin/env bash
# Parity smoke test for the :base dev container image content.
# Usage: docker run --rm -i IMAGE bash -s < smoke-test.sh
# Runs as the image's default user without network; root checks use sudo -n.
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
root_test() { sudo -n test "$@"; }
link_to() { [ -n "$1" ] && [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]; }
owned() {
    [ "$(stat -c %U "$1")" = "$2" ] && { [ -z "${3:-}" ] || [ "$(stat -c %G "$1")" = "$3" ]; }
}
# shellcheck disable=SC2016 # dpkg-query expands ${...} itself
pkg() { dpkg-query -W -f='${db:Status-Abbrev}\n' "$1" | grep -q '^ii'; }
header() { printf '#include <%s>\n' "$1" | gcc -E -x c - "${@:2}"; }
plugin_installed() { grep -Rqs -- "$1" ~/.claude/settings.json ~/.claude/plugins; }

# --- user and environment ----------------------------------------------------
check "user vscode" [ "$(id -un)" = vscode ]
check "uid 1000" [ "$(id -u)" = 1000 ]
check "gid 1000" [ "$(id -g)" = 1000 ]
for g in nvm python pipx ssh; do check "group ${g}" in_group "${g}"; done
check "passwordless sudo" sudo -n true
check "sudoers file" root_test -f /etc/sudoers.d/vscode
check "HOME" [ "${HOME}" = /home/vscode ]
check "WORKDIR" [ "${PWD}" = /home/vscode ]
check "LANG" env_is LANG C.UTF-8
check "locale en_US.UTF-8" sh -c 'locale -a | grep -qix en_US.utf8'
check "NVM_DIR" env_is NVM_DIR /usr/local/share/nvm
check "NVM_SYMLINK_CURRENT" env_is NVM_SYMLINK_CURRENT true
check "PYTHON_PATH" env_is PYTHON_PATH /usr/local/python/current
check "PIPX_HOME" env_is PIPX_HOME /usr/local/py-utils
check "PIPX_BIN_DIR" env_is PIPX_BIN_DIR /usr/local/py-utils/bin
check "ENABLE_LSP_TOOL" env_is ENABLE_LSP_TOOL 1
check "DEBIAN_FRONTEND" env_is DEBIAN_FRONTEND noninteractive
for d in /usr/local/python/current/bin /usr/local/py-utils/bin \
    /usr/local/jupyter /usr/local/share/nvm/current/bin /home/vscode/.local/bin \
    /usr/local/sbin /usr/local/bin /usr/sbin /usr/bin /sbin /bin; do
    check "PATH ${d}" in_path "${d}"
done

# --- Debian packages: commands, packages without commands, headers -----------
# buildpack-deps curl, common-utils, Dockerfile.mcr-trixie, git build deps,
# sshd, and python lists; virtual package names are checked via a command.
for c in curl wget gpg sq ssh dirmngr ip ps lsof htop netstat killall pstree \
    tree rsync unzip bzip2 xz zip nano vi less jq lsb_release dialog \
    locale-gen sudo ncdu man strace bwrap slirp4netns iptables socat zsh \
    batcat bats eza fastfetch fdfind fzf delta just lazygit mc pass rg \
    shellcheck vim xh gcc g++ make msgfmt sshd tar; do
    check "command ${c}" has "${c}"
done
for p in ca-certificates netbase apt-utils bash-completion libkrb5-3 \
    libgssapi-krb5-2 'libicu[0-9][0-9]' 'liblttng-ust[0-9]*' libstdc++6 \
    zlib1g locales manpages manpages-dev init-system-helpers util-linux \
    bats-assert bats-file vim-doc vim-scripts build-essential gettext \
    libpcre2-posix3 libatomic1 openssh-server tk-dev libxmlsec1-dev \
    python3-doc python3-tk python3-venv python3-dev python3-pip pipx; do
    check "package ${p}" pkg "${p}"
done
for h in zlib.h openssl/ssl.h curl/curl.h expat.h bzlib.h ffi.h gdbm.h \
    lzma.h ncurses.h readline/readline.h sqlite3.h uuid/uuid.h; do
    check "header ${h}" header "${h}"
done
check "header pcre2.h" header pcre2.h -DPCRE2_CODE_UNIT_WIDTH=8
check "header libxml/parser.h" header libxml/parser.h -I/usr/include/libxml2
# shellcheck disable=SC2046 # python3-config prints several flags
check "header Python.h" header Python.h $(python3-config --includes 2>/dev/null)

# --- git: source build in /usr/local/bin, apt git in /usr/bin ----------------
check "git source build" test -x /usr/local/bin/git
check "git on PATH is source build" [ "$(command -v git)" = /usr/local/bin/git ]
check "git apt" test -x /usr/bin/git

# --- shells: rc snippets, zsh with Oh My Zsh, shims --------------------------
check "oh-my-zsh user" test -f ~/.oh-my-zsh/oh-my-zsh.sh
check "oh-my-zsh root" root_test -f /root/.oh-my-zsh/oh-my-zsh.sh
check "zsh theme devcontainers" test -f ~/.oh-my-zsh/custom/themes/devcontainers.zsh-theme
check "zsh theme codespaces link" test -L ~/.oh-my-zsh/custom/themes/codespaces.zsh-theme
check "zshrc theme" file_has ~/.zshrc 'ZSH_THEME="devcontainers"'
check "zshrc no omz update" file_has ~/.zshrc "zstyle ':omz:update' mode disabled"
check "zshrc root" root_test -f /root/.zshrc
# shellcheck disable=SC2016 # literal text in the file
check "zprofile loads profile" file_has ~/.zprofile 'source $HOME/.profile'
check "bash.bashrc snippet" file_has /etc/bash.bashrc first-run-notice
check "zshrc snippet" file_has /etc/zsh/zshrc first-run-notice
check "bashrc prompt user" file_has ~/.bashrc __bash_prompt
check "bashrc prompt root" sudo -n grep -q __bash_prompt /root/.bashrc
# shellcheck disable=SC2016 # literal text in the file
check "bash.bashrc nvm" file_has /etc/bash.bashrc '. "$NVM_DIR/nvm.sh"'
check "bash.bashrc pipx" file_has /etc/bash.bashrc 'export PIPX_HOME="/usr/local/py-utils"'
check "zshrc nvm" file_has /etc/zsh/zshrc 'export NVM_DIR="/usr/local/share/nvm"'
check "profile.d PATH restore" test -x /etc/profile.d/00-restore-env.sh
check "code shim" test -x /usr/local/bin/code
check "systemctl shim" test -x /usr/local/bin/systemctl
check "home .config owner" owned ~/.config vscode

# --- Dockerfile.mcr-trixie home folders and uv -------------------------------
check "home .vscode-server/data/User" test -d ~/.vscode-server/data/User
check "home .ssh mode 700" [ "$(stat -c %a ~/.ssh)" = 700 ]
check "home .local owner" owned ~/.local vscode
check "home .cache owner" owned ~/.cache vscode
check "uv" test -x ~/.local/bin/uv
check "uvx" test -x ~/.local/bin/uvx
check "uv cache" test -d ~/.cache/uv

# --- sshd --------------------------------------------------------------------
check "sshd Port 2222" grep -qx 'Port 2222' /etc/ssh/sshd_config
check "sshd PermitRootLogin yes" grep -qx 'PermitRootLogin yes' /etc/ssh/sshd_config
check "sshd UsePAM yes" grep -qx 'UsePAM yes' /etc/ssh/sshd_config
check "pam_loginuid optional" grep -Eq '^session\s+optional\s+pam_loginuid\.so' /etc/pam.d/sshd
check "ssh-init.sh" test -x /usr/local/share/ssh-init.sh
check "init.d ssh" test -x /etc/init.d/ssh
check "/run/sshd" test -d /run/sshd

# --- node, npm globals -------------------------------------------------------
check "node 24" sh -c 'node --version | grep -q "^v24\."'
for c in npm yarn corepack; do check "command ${c}" has "${c}"; done
check "nvm.sh" test -s /usr/local/share/nvm/nvm.sh
check "nvm current link" test -L /usr/local/share/nvm/current
check "NVM_DIR vscode:nvm" owned /usr/local/share/nvm vscode nvm
check "NVM_DIR setgid" test -g /usr/local/share/nvm
for c in eslint tsc pyright pyright-langserver typescript-language-server editorconfig; do
    check "npm global ${c}" has "${c}"
done

# --- python, pipx tools ------------------------------------------------------
for c in python3 python pydoc3 python3-config pip pip3 pipx; do
    check "command ${c}" has "${c}"
done
for l in python3 python pydoc3 pydoc python3-config python-config; do
    check "python current/bin/${l}" test -L "/usr/local/python/current/bin/${l}"
done
check "/usr/local/python vscode:python" owned /usr/local/python vscode python
check "/usr/local/py-utils vscode:pipx" owned /usr/local/py-utils vscode pipx
for t in flake8 autopep8 black yapf mypy pydocstyle pycodestyle bandit \
    pipenv virtualenv pytest pylint; do
    check "pipx tool ${t}" test -x "/usr/local/py-utils/bin/${t}"
done
check "python tkinter" python3 -c 'import tkinter'
check "python venv" python3 -m venv --help

# --- standalone CLIs and their files -----------------------------------------
check "gh" has gh
check "copilot" test -x /usr/local/bin/copilot
check "copilot auto-update flag" test -f /etc/devcontainer-copilot-cli/auto-update
check "claude" has claude
check "claude system link" test -L /usr/local/bin/claude
check "claude link target" link_to /usr/local/bin/claude ~/.local/bin/claude
check "claude plugin pyright-lsp" plugin_installed pyright-lsp@claude-plugins-official
check "claude plugin typescript-lsp" plugin_installed typescript-lsp@claude-plugins-official
check "specify" has specify
check "specify system link" test -L /usr/local/bin/specify
check "otelcol-contrib" test -x /usr/local/bin/otelcol-contrib
check "otel config OTLP" file_has /etc/otelcol-contrib/config.yaml 'endpoint: localhost:4317'
check "otel config exporter" file_has /etc/otelcol-contrib/config.yaml 'azuremonitor:'
check "otel start hook" test -x /usr/local/share/otel-collector-contrib/start.sh
check "otel autostart off" file_has /usr/local/share/otel-collector-contrib/start.sh 'AUTO_START="false"'
check "spf" test -x /usr/local/bin/spf
check "bat link to batcat" link_to /usr/local/bin/bat /usr/bin/batcat
check "superfile config" file_has ~/.config/superfile/config.toml 'auto_check_update = false'
check "superfile bat preview" file_has ~/.config/superfile/config.toml 'code_previewer = "bat"'
check "herdr" test -x /usr/local/bin/herdr
check "herdr-core" test -x /usr/local/bin/herdr-core
check "hc is herdr-core" link_to "$(command -v hc)" /usr/local/bin/herdr-core
check "herdr bash completion" test -f /usr/share/bash-completion/completions/herdr
check "herdr zsh completion" test -f /usr/local/share/zsh/site-functions/_herdr
check "herdr config" file_has ~/.config/herdr/config.toml 'onboarding = false'
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
# First output line of each command, then npm, pipx, uv, and dpkg inventories.
ver() {
    local name=$1
    shift
    printf '%s: %s\n' "${name}" "$("$@" </dev/null 2>&1 | head -n 1)"
}
echo
echo "=== versions"
ver debian cat /etc/debian_version
ver git git --version
ver git-apt /usr/bin/git --version
ver zsh zsh --version
ver openssh ssh -V
ver node node --version
ver npm npm --version
ver yarn yarn --version
ver python3 python3 --version
ver pipx pipx --version
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
echo "=== pipx tools"
pipx list --short </dev/null 2>/dev/null | sed -E 's|^([^ ]+) (.*)$|pipx/\1: \2|'
echo "=== uv tools"
uv tool list </dev/null 2>/dev/null | sed -nE 's|^([^- ][^ ]*) (v.*)$|uv/\1: \2|p'
echo "=== dpkg packages"
# shellcheck disable=SC2016 # dpkg-query expands ${...} itself
dpkg-query -W -f='dpkg/${Package}: ${Version}\n' | sort

[ "${failures}" -eq 0 ]
