# Plain single-Dockerfile build of the :base dev container image.
# Reproduces .devcontainer/base (Dockerfile.mcr-trixie plus all its Features)
# with "docker build" only: no devcontainer CLI, Features, or MCR base image.
# Parity build: same packages, files, and config as the Feature build, so a
# size difference shows only the overhead of the build method.
FROM debian:trixie

# Bash with pipefail, so a failed download inside a pipe fails the build.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The user the Feature build creates (common-utils options of the MCR image);
# an account name, so the DL3064 secret warning does not apply.
# hadolint ignore=DL3064
ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}

# LANG comes from the MCR base image, DEBIAN_FRONTEND from
# Dockerfile.mcr-trixie; both stay in the image config, as there.
ENV LANG=C.UTF-8 \
    DEBIAN_FRONTEND=noninteractive

# Layer 1 – all Debian packages, so dpkg state, logs, and the locale archive
# are written once. Blocks follow the Feature build's order; versions float
# and recommends stay off except for zsh, as in the Features. SHELL is bash:
# hadolint checks apt-get arguments as POSIX sh (SC3054).
# hadolint ignore=DL3008,DL3015,SC3054
RUN <<'EOF'
set -ex
apt-get update
# MCR base image: the buildpack-deps:trixie-curl packages and an upgrade
apt-get -y install --no-install-recommends \
    ca-certificates curl gnupg netbase sq wget
apt-get -y upgrade
# common-utils 2.7.1: its package list, libssl packages apt finds by that
# exact name, and git, which is still missing at this point
pkgs=(apt-utils bash-completion openssh-client gnupg2 dirmngr iproute2 procps
    lsof htop net-tools psmisc curl tree wget rsync ca-certificates unzip
    bzip2 xz-utils zip nano vim-tiny less jq lsb-release apt-transport-https
    dialog libc6 libgcc1 libkrb5-3 libgssapi-krb5-2 'libicu[0-9][0-9]'
    'liblttng-ust[0-9]' libstdc++6 zlib1g locales sudo ncdu man-db strace
    manpages manpages-dev init-system-helpers bubblewrap slirp4netns
    util-linux iptables socat)
for lib in libssl1.1 libssl3; do
    if [ -n "$(apt-cache --names-only search "^${lib}$")" ]; then
        pkgs+=("${lib}")
    fi
done
pkgs+=(git)
apt-get -y install --no-install-recommends "${pkgs[@]}"
# common-utils: zsh with its recommends, upgrade, autoremove, en_US locale
apt-get -y install zsh
apt-get -y upgrade --no-install-recommends
apt-get -y autoremove
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
# git 1.3.8 ("latest" in the MCR base image): build dependencies, which the
# Feature leaves installed; the source build is the next layer
apt-get -y install --no-install-recommends build-essential curl \
    ca-certificates tar gettext libssl-dev zlib1g-dev 'libcurl?-openssl-dev' \
    libexpat1-dev
apt-get -y install --no-install-recommends libpcre2-dev
apt-get -y install --no-install-recommends libpcre2-posix3
# Dockerfile.mcr-trixie: CLI tools (its own upgrade is a no-op by now)
apt-get -y install --no-install-recommends bat bats bats-assert bats-file \
    ca-certificates curl eza fastfetch fd-find fzf git-delta gnupg2 jq just \
    lazygit mc pass ripgrep shellcheck sudo vim vim-doc vim-scripts xh
# node 2.1.2 prerequisites; copilot-cli, github-cli, and speckit need no
# packages beyond the ones above
apt-get -y install --no-install-recommends apt-transport-https curl \
    ca-certificates tar gnupg2 dirmngr libatomic1
# python 1.8.1 (os-provided): its source-build dependencies, installed even
# for os-provided, the Debian python packages, and pipx for the tools
apt-get -y install --no-install-recommends ca-certificates curl dirmngr gcc \
    gnupg2 libbz2-dev libffi-dev libgdbm-dev liblzma-dev libncurses5-dev \
    libreadline-dev libsqlite3-dev libssl-dev libxml2-dev libxmlsec1-dev make \
    tar tk-dev uuid-dev xz-utils zlib1g-dev
apt-get -y install --no-install-recommends python3 python3-doc python3-pip \
    python3-venv python3-dev python3-tk
apt-get -y install --no-install-recommends pipx
# sshd 1.1.0
apt-get -y install --no-install-recommends openssh-server openssh-client lsof
# github-cli 1.1.3: newest x.y.z tag of cli/cli as .deb from GitHub releases
gh_version="$(git ls-remote --tags https://github.com/cli/cli \
    | grep -oE 'tags/v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's|^tags/v||' \
    | sort -rVu | sed -n '1p')"
gh_deb="gh_${gh_version}_linux_$(dpkg --print-architecture).deb"
mkdir -p /tmp/ghcli
curl -fsSL -o "/tmp/ghcli/${gh_deb}" \
    "https://github.com/cli/cli/releases/download/v${gh_version}/${gh_deb}"
dpkg -i "/tmp/ghcli/${gh_deb}"
rm -rf /tmp/ghcli
# Dockerfile.mcr-trixie cleanup; every Feature removes the apt lists, too
apt-get clean
rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*
EOF

# Layer 2 – git 1.3.8 ("latest" in the MCR base image): the newest tag on
# the first page of the GitHub tags API, built into /usr/local as there.
# SHELL is bash; hadolint checks this array use as POSIX sh (SC3054).
# hadolint ignore=SC3054
RUN <<'EOF'
set -ex
git_version="$(curl -fsSL -H 'Accept: application/vnd.github.v3+json' \
    https://api.github.com/repos/git/git/tags \
    | grep -oP '"name":\s*"v\K[0-9]+\.[0-9]+\.[0-9]+"' | tr -d '"' \
    | sort -rV | sed -n '1p')"
curl -sL "https://github.com/git/git/archive/v${git_version}.tar.gz" \
    | tar -xzC /tmp
src="/tmp/git-${git_version}"
git_options=(prefix=/usr/local sysconfdir=/etc USE_LIBPCRE=YesPlease
    NO_RUST=YesPlease)
make -C "${src}" -s "${git_options[@]}" all
make -C "${src}" -s "${git_options[@]}" install
rm -rf "${src}"
EOF

# Layer 3 – common-utils 2.7.1 with the MCR options (user, sudo, rc
# snippets, zsh with Oh My Zsh, shims), the Dockerfile.mcr-trixie home
# folders, and sshd 1.1.0 on port 2222. SHELL is bash; hadolint checks
# common-utils' "echo -e" as POSIX sh (SC3037).
# hadolint ignore=SC3037
RUN <<'EOF'
set -ex
home="/home/${USERNAME}"
# vscode user with passwordless sudo
groupadd --gid "${USER_GID}" "${USERNAME}"
useradd -s /bin/bash --uid "${USER_UID}" --gid "${USERNAME}" -m "${USERNAME}"
echo "${USERNAME} ALL=(root) NOPASSWD:ALL" > "/etc/sudoers.d/${USERNAME}"
chmod 0440 "/etc/sudoers.d/${USERNAME}"
# skeleton rc files that useradd did not copy
for rc_file in .bashrc .profile .zshrc .zprofile; do
    if [ -f "/etc/skel/${rc_file}" ] \
        && { [ ! -e "${home}/${rc_file}" ] || [ ! -s "${home}/${rc_file}" ]; }; then
        cp "/etc/skel/${rc_file}" "${home}/${rc_file}"
        chown "${USERNAME}:${USERNAME}" "${home}/${rc_file}"
    fi
done
# global rc snippet for bash, prompt theme in the user's and root's bashrc
cat > /tmp/rc_snippet.sh <<'RCSNIPPET'
if [ -z "${USER}" ]; then export USER=$(whoami); fi
if [[ "${PATH}" != *"$HOME/.local/bin"* ]]; then export PATH="${PATH}:$HOME/.local/bin"; fi

# Display optional first run image specific notice if configured and terminal is interactive
if [ -t 1 ] && [[ "${TERM_PROGRAM}" = "vscode" || "${TERM_PROGRAM}" = "codespaces" ]] && [ ! -f "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed" ]; then
    if [ -f "/usr/local/etc/vscode-dev-containers/first-run-notice.txt" ]; then
        cat "/usr/local/etc/vscode-dev-containers/first-run-notice.txt"
    elif [ -f "/workspaces/.codespaces/shared/first-run-notice.txt" ]; then
        cat "/workspaces/.codespaces/shared/first-run-notice.txt"
    fi
    mkdir -p "$HOME/.config/vscode-dev-containers"
    # Mark first run notice as displayed after 10s to avoid problems with fast terminal refreshes hiding it
    ((sleep 10s; touch "$HOME/.config/vscode-dev-containers/first-run-notice-already-displayed") &)
fi

# Set the default git editor if not already set
if [ -z "$(git config --get core.editor)" ] && [ -z "${GIT_EDITOR}" ]; then
    if  [ "${TERM_PROGRAM}" = "vscode" ]; then
        if [[ -n $(command -v code-insiders) &&  -z $(command -v code) ]]; then
            export GIT_EDITOR="code-insiders --wait"
        else
            export GIT_EDITOR="code --wait"
        fi
    fi
fi
RCSNIPPET
cat > /tmp/bash_theme_snippet.sh <<'BASHTHEME'
# bash theme - partly inspired by https://github.com/ohmyzsh/ohmyzsh/blob/master/themes/robbyrussell.zsh-theme
__bash_prompt() {
    local userpart='`export XIT=$? \
        && [ ! -z "${GITHUB_USER:-}" ] && echo -n "\[\033[0;32m\]@${GITHUB_USER:-} " || echo -n "\[\033[0;32m\]\u " \
        && [ "$XIT" -ne "0" ] && echo -n "\[\033[1;31m\]➜" || echo -n "\[\033[0m\]➜"`'
    local gitbranch='`\
        if [ "$(git config --get devcontainers-theme.hide-status 2>/dev/null)" != 1 ] && [ "$(git config --get codespaces-theme.hide-status 2>/dev/null)" != 1 ]; then \
            export BRANCH="$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks rev-parse --short HEAD 2>/dev/null)"; \
            if [ "${BRANCH:-}" != "" ]; then \
                echo -n "\[\033[0;36m\](\[\033[1;31m\]${BRANCH:-}" \
                && if [ "$(git config --get devcontainers-theme.show-dirty 2>/dev/null)" = 1 ] && \
                    git --no-optional-locks ls-files --error-unmatch -m --directory --no-empty-directory -o --exclude-standard ":/*" > /dev/null 2>&1; then \
                        echo -n " \[\033[1;33m\]✗"; \
                fi \
                && echo -n "\[\033[0;36m\]) "; \
            fi; \
        fi`'
    local lightblue='\[\033[1;34m\]'
    local removecolor='\[\033[0m\]'
    PS1="${userpart} ${lightblue}\w ${gitbranch}${removecolor}\$ "
    unset -f __bash_prompt
}
__bash_prompt
export PROMPT_DIRTRIM=4

# Check if the terminal is xterm
if [[ "$TERM" == "xterm" ]]; then
    # Function to set the terminal title to the current command
    preexec() {
        local cmd="${BASH_COMMAND}"
        echo -ne "\033]0;${USER}@${HOSTNAME}: ${cmd}\007"
    }

    # Function to reset the terminal title to the shell type after the command is executed
    precmd() {
        echo -ne "\033]0;${USER}@${HOSTNAME}: ${SHELL}\007"
    }

    # Trap DEBUG signal to call preexec before each command
    trap 'preexec' DEBUG

    # Append to PROMPT_COMMAND to call precmd before displaying the prompt
    PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }precmd"
fi
BASHTHEME
cat /tmp/rc_snippet.sh >> /etc/bash.bashrc
cat /tmp/bash_theme_snippet.sh >> "${home}/.bashrc"
cat /tmp/bash_theme_snippet.sh >> /root/.bashrc
chown "${USERNAME}:${USERNAME}" "${home}/.bashrc"
# zsh: .zprofile loads .profile, global rc snippet
touch "${home}/.zprofile"
# shellcheck disable=SC2016 # $HOME is meant literally
echo 'source $HOME/.profile' >> "${home}/.zprofile"
chown "${USERNAME}:${USERNAME}" "${home}/.zprofile"
cat /tmp/rc_snippet.sh >> /etc/zsh/zshrc
rm -f /tmp/rc_snippet.sh /tmp/bash_theme_snippet.sh
# Oh My Zsh for the user: shallow clone, repacked, devcontainers theme, and a
# .zshrc from its template with auto-update off; /root gets a copy later
umask g-w,o-w
omz="${home}/.oh-my-zsh"
mkdir -p "${omz}"
git clone --depth=1 -c core.eol=lf -c core.autocrlf=false \
    -c fsck.zeroPaddedFilemode=ignore -c fetch.fsck.zeroPaddedFilemode=ignore \
    -c receive.fsck.zeroPaddedFilemode=ignore \
    https://github.com/ohmyzsh/ohmyzsh "${omz}"
git -C "${omz}" repack -a -d -f --depth=1 --window=1
mkdir -p "${omz}/custom/themes"
cat > "${omz}/custom/themes/devcontainers.zsh-theme" <<'ZSHTHEME'
# Oh My Zsh! theme - partly inspired by https://github.com/ohmyzsh/ohmyzsh/blob/master/themes/robbyrussell.zsh-theme
__zsh_prompt() {
    local prompt_username
    if [ ! -z "${GITHUB_USER}" ]; then
        prompt_username="@${GITHUB_USER}"
    else
        prompt_username="%n"
    fi
    PROMPT="%{$fg[green]%}${prompt_username} %(?:%{$reset_color%}➜ :%{$fg_bold[red]%}➜ )" # User/exit code arrow
    PROMPT+='%{$fg_bold[blue]%}%(5~|%-1~/…/%3~|%4~)%{$reset_color%} ' # cwd
    PROMPT+='`\
        if [ "$(git config --get devcontainers-theme.hide-status 2>/dev/null)" != 1 ] && [ "$(git config --get codespaces-theme.hide-status 2>/dev/null)" != 1 ]; then \
            export BRANCH=$(git --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git --no-optional-locks rev-parse --short HEAD 2>/dev/null); \
            if [ "${BRANCH}" != "" ]; then \
                echo -n "%{$fg_bold[cyan]%}(%{$fg_bold[red]%}${BRANCH}" \
                && if [ "$(git config --get devcontainers-theme.show-dirty 2>/dev/null)" = 1 ] && \
                    git --no-optional-locks ls-files --error-unmatch -m --directory --no-empty-directory -o --exclude-standard ":/*" > /dev/null 2>&1; then \
                        echo -n " %{$fg_bold[yellow]%}✗"; \
                fi \
                && echo -n "%{$fg_bold[cyan]%})%{$reset_color%} "; \
            fi; \
        fi`'
    PROMPT+='%{$fg[white]%}$ %{$reset_color%}'
    unset -f __zsh_prompt
}
__zsh_prompt

# Check if the terminal is xterm
if [[ "$TERM" == "xterm" ]]; then
    # Function to set the terminal title to the current command
    preexec() {
        local cmd=${1}
        echo -ne "\033]0;${USER}@${HOSTNAME}: ${cmd}\007"
    }

    # Function to reset the terminal title to the shell type after the command is executed
    precmd() {
        echo -ne "\033]0;${USER}@${HOSTNAME}: ${SHELL}\007"
    }

    # Add the preexec and precmd functions to the corresponding hooks
    autoload -Uz add-zsh-hook
    add-zsh-hook preexec preexec
    add-zsh-hook precmd precmd
fi
ZSHTHEME
ln -sf "${omz}/custom/themes/devcontainers.zsh-theme" \
    "${omz}/custom/themes/codespaces.zsh-theme"
echo -e "$(cat "${omz}/templates/zshrc.zsh-template")\nzstyle ':omz:update' mode disabled" \
    > "${home}/.zshrc"
sed -i -e 's/ZSH_THEME=.*/ZSH_THEME="devcontainers"/g' "${home}/.zshrc"
chown -R "${USERNAME}:${USERNAME}" "${omz}" "${home}/.zshrc"
# ~/.config for the user, plus the code and systemctl shims
mkdir -p "${home}/.config"
chown "${USERNAME}:${USERNAME}" "${home}/.config"
cat > /usr/local/bin/code <<'CODESHIM'
#!/bin/sh

get_in_path_except_current() {
    which -a "$1" | grep -A1 "$0" | grep -v "$0"
}

code="$(get_in_path_except_current code)"

if [ -n "$code" ]; then
    exec "$code" "$@"
elif [ "$(command -v code-insiders)" ]; then
    exec code-insiders "$@"
else
    echo "code or code-insiders is not installed" >&2
    exit 127
fi
CODESHIM
chmod +rx /usr/local/bin/code
cat > /usr/local/bin/systemctl <<'SYSTEMCTLSHIM'
#!/bin/sh
set -e
if [ -d "/run/systemd/system" ]; then
    exec /bin/systemctl "$@"
else
    echo '\n"systemd" is not running in this container due to its overhead.\nUse the "service" command to start services instead. e.g.: \n\nservice --status-all'
fi
SYSTEMCTLSHIM
chmod +rx /usr/local/bin/systemctl
# Dockerfile.mcr-trixie: user folders that bind mounts expect
mkdir -p "${home}/.vscode-server/data/User" "${home}/.local" \
    "${home}/.cache" "${home}/.ssh"
chown -R "${USERNAME}:${USERNAME}" "${home}/.vscode-server/" \
    "${home}/.local/" "${home}/.cache/" "${home}/.ssh/"
chmod 700 "${home}/.ssh"
# sshd: ssh group, port 2222, root login and PAM on, optional login uid,
# and the init script that the Feature registers as its entrypoint
if ! getent group ssh >/dev/null; then groupadd ssh; fi
usermod -aG ssh "${USERNAME}"
mkdir -p /var/run/sshd
sed -i 's/session\s*required\s*pam_loginuid\.so/session optional pam_loginuid.so/g' \
    /etc/pam.d/sshd
sed -i 's/#*PermitRootLogin prohibit-password/PermitRootLogin yes/g' \
    /etc/ssh/sshd_config
sed -i -E 's/#*\s*Port\s+.+/Port 2222/g' /etc/ssh/sshd_config
sed -i 's/#GatewayPorts no/GatewayPorts no/g' /etc/ssh/sshd_config
sed -i -E 's/#?\s*UsePAM\s+.+/UsePAM yes/g' /etc/ssh/sshd_config
cat > /usr/local/share/ssh-init.sh <<'SSHINIT'
#!/usr/bin/env bash
# This script is intended to be run as root with a container that runs as root (even if you connect with a different user)
# However, it supports running as a user other than root if passwordless sudo is configured for that same user.

set -e 

sudoIf()
{
    if [ "$(id -u)" -ne 0 ]; then
        sudo "$@"
    else
        "$@"
    fi
}


# ** Start SSH server **
sudoIf /etc/init.d/ssh start 2>&1 | sudoIf tee /tmp/sshd.log > /dev/null

set +e
exec "$@"
SSHINIT
chmod +x /usr/local/share/ssh-init.sh
EOF

# Layer 4 – Dockerfile.mcr-trixie: uv in ~/.local/bin, installed as the
# user, so its installer edits the user's rc files; its cache is dropped.
# hadolint ignore=DL3066
USER ${USERNAME}
WORKDIR /home/${USERNAME}
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
RUN curl -LsSf https://astral.sh/uv/install.sh | sh && rm -rf "$HOME/.cache"/*
# hadolint ignore=DL3066
USER root

# Layer 5 – the Feature build's second common-utils run copies the user's
# zsh setup, by now with uv's rc edit, to /root; then the release binaries
# of otel-collector-contrib, copilot-cli, superfile, and herdr.
RUN <<'EOF'
set -ex
home="/home/${USERNAME}"
cp -rf "${home}/.oh-my-zsh" "${home}/.zshrc" /root
# otel-collector-contrib 1.0.0 (autoStart false): latest release binary,
# default OTLP to Azure Monitor config, start hook with its options baked in
case "$(uname -m)" in
    x86_64) arch=amd64 ;;
    aarch64 | armv8*) arch=arm64 ;;
    *) echo "unsupported architecture $(uname -m)"; exit 1 ;;
esac
releases=https://github.com/open-telemetry/opentelemetry-collector-releases
tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${releases}/releases/latest" \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$')"
version="${tag#v}"
tmpdir="$(mktemp -d)"
curl -fsSL -o "${tmpdir}/otelcol-contrib.tar.gz" \
    "${releases}/releases/download/v${version}/otelcol-contrib_${version}_linux_${arch}.tar.gz"
tar -xzf "${tmpdir}/otelcol-contrib.tar.gz" -C "${tmpdir}" otelcol-contrib
install -m 0755 "${tmpdir}/otelcol-contrib" /usr/local/bin/otelcol-contrib
rm -rf "${tmpdir}"
GRPC_PORT=4317
HTTP_PORT=4318
AUTO_START=false
CUSTOM_CONFIG_PATH=""
EFFECTIVE_CONFIG=/etc/otelcol-contrib/config.yaml
mkdir -p /etc/otelcol-contrib
cat > /etc/otelcol-contrib/config.yaml <<OTELCONFIG
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: localhost:${GRPC_PORT}
      http:
        endpoint: localhost:${HTTP_PORT}

processors:
  batch:

exporters:
  azuremonitor:
    connection_string: "\${env:APPLICATIONINSIGHTS_CONNECTION_STRING}"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [azuremonitor]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [azuremonitor]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [azuremonitor]
OTELCONFIG
chmod 0644 /etc/otelcol-contrib/config.yaml
mkdir -p /usr/local/share/otel-collector-contrib
cat > /usr/local/share/otel-collector-contrib/start.sh <<OTELSTART
#!/bin/bash
# Auto-start hook for the otel-collector-contrib devcontainer Feature.
# Baked in at Feature install time:
AUTO_START="${AUTO_START}"
CONFIG="${EFFECTIVE_CONFIG}"
USING_DEFAULT_CONFIG="$([ -z "${CUSTOM_CONFIG_PATH}" ] && echo true || echo false)"

LOG_FILE="/tmp/otelcol-contrib.log"
PID_FILE="/tmp/otelcol-contrib.pid"

if [ "\${AUTO_START}" != "true" ]; then
    exit 0
fi

# postStartCommand fires on every container (re)start - don't stack instances
if [ -f "\${PID_FILE}" ] && kill -0 "\$(cat "\${PID_FILE}")" 2>/dev/null; then
    echo "otelcol-contrib already running (pid \$(cat "\${PID_FILE}"))."
    exit 0
fi

# The default config resolves \${env:APPLICATIONINSIGHTS_CONNECTION_STRING}
# at collector startup - without it the azuremonitorexporter cannot start,
# so skip (never fail the container start over missing telemetry).
if [ "\${USING_DEFAULT_CONFIG}" = "true" ] && [ -z "\${APPLICATIONINSIGHTS_CONNECTION_STRING}" ]; then
    echo "WARNING: APPLICATIONINSIGHTS_CONNECTION_STRING is not set - not starting otelcol-contrib." | tee -a "\${LOG_FILE}"
    echo "Provide it via containerEnv/remoteEnv (see the otel-collector-contrib Feature README) and restart the container, or run \${0} again." | tee -a "\${LOG_FILE}"
    exit 0
fi

if [ ! -f "\${CONFIG}" ]; then
    echo "WARNING: collector config '\${CONFIG}' not found - not starting otelcol-contrib." | tee -a "\${LOG_FILE}"
    exit 0
fi

echo "Starting otelcol-contrib with config \${CONFIG} (log: \${LOG_FILE})..."
nohup /usr/local/bin/otelcol-contrib --config "\${CONFIG}" >> "\${LOG_FILE}" 2>&1 &
echo \$! > "\${PID_FILE}"
OTELSTART
chmod 0755 /usr/local/share/otel-collector-contrib/start.sh
# copilot-cli 1.1.4: latest release binary; the flag file enables the
# Feature's per-start update check, which only a dev container runs
arch="$(dpkg --print-architecture)"
if [ "${arch}" = amd64 ]; then arch=x64; fi
mkdir -p /tmp/copilotcli
curl -fsSL -o "/tmp/copilotcli/copilot-linux-${arch}.tar.gz" \
    "https://github.com/github/copilot-cli/releases/latest/download/copilot-linux-${arch}.tar.gz"
tar -xzf "/tmp/copilotcli/copilot-linux-${arch}.tar.gz" -C /tmp/copilotcli
mv /tmp/copilotcli/copilot /usr/local/bin/copilot
rm -rf /tmp/copilotcli
mkdir -p /etc/devcontainer-copilot-cli
touch /etc/devcontainer-copilot-cli/auto-update
# superfile 1.2.0: latest spf release binary and a bat link to batcat
case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 ;;
    aarch64 | arm64 | armv8*) arch=arm64 ;;
    *) echo "unsupported architecture $(uname -m)"; exit 1 ;;
esac
releases=https://github.com/yorukot/superfile
tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "${releases}/releases/latest" \
    | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+$')"
version="${tag#v}"
asset="superfile-linux-v${version}-${arch}"
tmpdir="$(mktemp -d)"
mkdir -p "${tmpdir}/extract"
curl -fsSL -o "${tmpdir}/superfile.tar.gz" \
    "${releases}/releases/download/v${version}/${asset}.tar.gz"
tar --warning=no-unknown-keyword -xzf "${tmpdir}/superfile.tar.gz" \
    -C "${tmpdir}/extract"
install -m 0755 "$(find "${tmpdir}/extract" -type f -name spf -print -quit)" \
    /usr/local/bin/spf
rm -rf "${tmpdir}"
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    ln -sf "$(command -v batcat)" /usr/local/bin/bat
fi
# herdr 2.0.0: upstream's install scripts, unchanged, into /usr/local/bin,
# plus bash and zsh completions; its config and skill follow in layer 7
herdr_fetch() {
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 "$1" -o "$2"
}
tmpdir="$(mktemp -d)"
herdr_fetch https://herdr.dev/install.sh "${tmpdir}/herdr-install.sh"
HERDR_INSTALL_DIR=/usr/local/bin sh "${tmpdir}/herdr-install.sh"
mkdir -p /usr/share/bash-completion/completions \
    /usr/local/share/zsh/site-functions
/usr/local/bin/herdr completion bash > /usr/share/bash-completion/completions/herdr
/usr/local/bin/herdr completion zsh > /usr/local/share/zsh/site-functions/_herdr
chmod 0644 /usr/share/bash-completion/completions/herdr \
    /usr/local/share/zsh/site-functions/_herdr
herdr_fetch https://releases.herdr.dev/core/install.sh \
    "${tmpdir}/herdr-core-install.sh"
rm -f /usr/local/bin/herdr-core
HC_VERSION="" HC_INSTALL_DIR=/usr/local/bin sh "${tmpdir}/herdr-core-install.sh"
rm -rf "${tmpdir}"
EOF

# node 2.1.2 and python 1.8.1 container env; the devcontainer CLI also sets
# it right before their install steps, so later steps see the same PATH.
ENV NVM_DIR=/usr/local/share/nvm \
    NVM_SYMLINK_CURRENT=true \
    PATH="/usr/local/share/nvm/current/bin:${PATH}"
ENV PYTHON_PATH=/usr/local/python/current \
    PIPX_HOME=/usr/local/py-utils \
    PIPX_BIN_DIR=/usr/local/py-utils/bin \
    PATH="/usr/local/python/current/bin:/usr/local/py-utils/bin:/usr/local/jupyter:${PATH}"

# Layer 6 – node 2.1.2 (node 24 through nvm, yarn through corepack), python
# 1.8.1 (os-provided, 12 pipx tools), and the npm-packages Feature; tool
# versions float, as in the Features. SHELL is bash; hadolint checks the
# PATH substitution as POSIX sh (SC3060).
# hadolint ignore=DL3013,SC3060
RUN <<'EOF'
set -ex
# Append a line to the global bash and zsh rc files once, as both do.
updaterc() {
    if [[ "$(cat /etc/bash.bashrc)" != *"$1"* ]]; then
        echo -e "$1" >> /etc/bash.bashrc
    fi
    if [ -f /etc/zsh/zshrc ] && [[ "$(cat /etc/zsh/zshrc)" != *"$1"* ]]; then
        echo -e "$1" >> /etc/zsh/zshrc
    fi
}
# node: nvm (newest tag) installs node 24 as the user into the shared,
# group-writable NVM_DIR; npm and pnpm stay as shipped (both "none")
(
    if ! grep -e "^nvm:" /etc/group >/dev/null 2>&1; then groupadd -r nvm; fi
    usermod -a -G nvm "${USERNAME}"
    umask 0002
    mkdir -p "${NVM_DIR}"
    chown "${USERNAME}:nvm" "${NVM_DIR}"
    chmod g+rws "${NVM_DIR}"
    nvm_version="$(git ls-remote --tags https://github.com/nvm-sh/nvm \
        | grep -oE 'tags/v[0-9]+\.[0-9]+\.[0-9]+$' | sed 's|^tags/v||' \
        | sort -rVu | sed -n '1p')"
    su "${USERNAME}" -c "set -e; umask 0002; export PROFILE=/dev/null NODE_VERSION=24; curl -so- 'https://raw.githubusercontent.com/nvm-sh/nvm/v${nvm_version}/install.sh' | bash; . '${NVM_DIR}/nvm.sh'; nvm alias default 24"
    # shellcheck disable=SC2016 # $NVM_DIR is meant literally
    updaterc 'export NVM_DIR="/usr/local/share/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"'
    # yarn: corepack shims when node ships corepack, else npm
    nvm_use=". '${NVM_DIR}/nvm.sh' && nvm use node"
    if ! bash -c "${nvm_use} && type yarn >/dev/null 2>&1"; then
        if bash -c "${nvm_use} && type corepack >/dev/null 2>&1"; then
            su "${USERNAME}" -c "umask 0002 && ${nvm_use} && corepack enable"
        fi
        if ! bash -c "${nvm_use} && type yarn >/dev/null 2>&1"; then
            su "${USERNAME}" -c "umask 0002 && ${nvm_use} && npm install --global yarn"
        fi
    fi
    su "${USERNAME}" -c "umask 0002 && . '${NVM_DIR}/nvm.sh' && nvm clear-cache"
    mkdir -p "${NVM_DIR}/versions"
    chmod -R g+rw "${NVM_DIR}/versions"
)
# python: PATH restore file for login shells, python group with links in
# /usr/local/python/current, a pip link if missing, then the pipx tools
(
    rm -f /etc/profile.d/00-restore-env.sh
    # shellcheck disable=SC2016 # $PATH is expanded by the login shell
    echo "export PATH=${PATH//$(sh -lc 'echo $PATH')/\$PATH}" \
        > /etc/profile.d/00-restore-env.sh
    chmod +x /etc/profile.d/00-restore-env.sh
    if ! grep -e "^python:" /etc/group >/dev/null 2>&1; then groupadd -r python; fi
    usermod -a -G python "${USERNAME}"
    mkdir -p "${PYTHON_PATH}/bin"
    ln -s /usr/bin/python3 "${PYTHON_PATH}/bin/python3"
    ln -s /usr/bin/python3 "${PYTHON_PATH}/bin/python"
    ln -s /usr/bin/pydoc3 "${PYTHON_PATH}/bin/pydoc3"
    ln -s /usr/bin/pydoc3 "${PYTHON_PATH}/bin/pydoc"
    ln -s /usr/bin/python3-config "${PYTHON_PATH}/bin/python3-config"
    ln -s /usr/bin/python3-config "${PYTHON_PATH}/bin/python-config"
    chown -R "${USERNAME}:python" /usr/local/python
    chmod -R g+r+w /usr/local/python
    find /usr/local/python -type d -print0 | xargs -0 -n 1 chmod g+s
    if ! type pip >/dev/null 2>&1 && type pip3 >/dev/null 2>&1; then
        ln -s /usr/bin/pip3 /usr/bin/pip
    fi
    # pipx tools: shared, group-writable PIPX_HOME, one venv per tool with
    # system site packages and no pip cache, as python 1.8.1 does
    if ! grep -e "^pipx:" /etc/group >/dev/null 2>&1; then groupadd -r pipx; fi
    usermod -a -G pipx "${USERNAME}"
    umask 0002
    mkdir -p "${PIPX_BIN_DIR}"
    chown -R "${USERNAME}:pipx" "${PIPX_HOME}"
    chmod -R g+r+w "${PIPX_HOME}"
    find "${PIPX_HOME}" -type d -print0 | xargs -0 -n 1 chmod g+s
    export PYTHONUSERBASE=/tmp/pip-tmp PIP_CACHE_DIR=/tmp/pip-tmp/cache
    for util in flake8 autopep8 black yapf mypy pydocstyle pycodestyle bandit \
        pipenv virtualenv pytest pylint; do
        if ! type "${util}" >/dev/null 2>&1; then
            pipx install --system-site-packages \
                --pip-args '--no-cache-dir --force-reinstall' "${util}"
        fi
    done
    rm -rf /tmp/pip-tmp
    updaterc "export PIPX_HOME=\"${PIPX_HOME}\""
    updaterc "export PIPX_BIN_DIR=\"${PIPX_BIN_DIR}\""
    updaterc "if [[ \"\${PATH}\" != *\"\${PIPX_BIN_DIR}\"* ]]; then export PATH=\"\${PATH}:\${PIPX_BIN_DIR}\"; fi"
)
# npm-packages (local Feature): global language servers and linters,
# installed as the user; the npm cache is cleaned in the same step
su "${USERNAME}" -c "export PATH='${NVM_DIR}/current/bin:${PATH}'; npm install -g editorconfig eslint typescript pyright typescript-language-server && npm cache clean --force"
EOF

# claude-code 1.1.3 container env, set before its install as by the CLI.
ENV ENABLE_LSP_TOOL=1

# Layer 7 – claude-code, speckit, superfile config, lsp-config, and herdr
# config and skill, in Feature order; user-scope steps run as the user.
RUN <<'EOF'
set -ex
home="/home/${USERNAME}"
# claude-code: native installer as the user (login shell), a system link,
# then the pyright and typescript LSP plugins at user scope (non-fatal)
su - "${USERNAME}" -c "curl -fsSL https://claude.ai/install.sh | bash -s -- latest"
ln -sf "${home}/.local/bin/claude" /usr/local/bin/claude
su - "${USERNAME}" -c "claude plugin marketplace add anthropics/claude-plugins-official --scope user" \
    || echo "WARNING: could not add marketplace 'anthropics/claude-plugins-official' (continuing)"
for plugin in pyright-lsp@claude-plugins-official typescript-lsp@claude-plugins-official; do
    su - "${USERNAME}" -c "claude plugin install ${plugin} --scope user" \
        || echo "WARNING: could not install plugin '${plugin}' - skipping"
done
# speckit: newest spec-kit tag installed with uv as the user, plus a system
# link; uv's cache stays in the image, as in the Feature
spec_version="$(git ls-remote --tags https://github.com/github/spec-kit \
    | grep -oP 'tags/v\K[0-9]+\.[0-9]+\.[0-9]+$' | sort -rV | sed -n '1p')"
su "${USERNAME}" -c "export PATH='${home}/.local/bin:${PATH}'; uv tool install specify-cli --from git+https://github.com/github/spec-kit.git@v${spec_version}"
uv_bin_dir="$(su "${USERNAME}" -c "export PATH='${home}/.local/bin:${PATH}'; uv tool dir --bin")"
ln -sf "${uv_bin_dir}/specify" /usr/local/bin/specify
# superfile defaults: partial config; plugin toggles follow what is on PATH
# (exiftool and zoxide are absent, bat is linked in layer 5)
NERDFONT=false
CD_ON_QUIT=false
if command -v exiftool >/dev/null 2>&1; then CFG_METADATA=true; else CFG_METADATA=false; fi
if command -v bat >/dev/null 2>&1; then CFG_CODE_PREVIEWER='"bat"'; else CFG_CODE_PREVIEWER='""'; fi
if command -v zoxide >/dev/null 2>&1; then CFG_ZOXIDE=true; else CFG_ZOXIDE=false; fi
mkdir -p "${home}/.config/superfile"
cat > "${home}/.config/superfile/config.toml" <<SPFCONFIG
##############################################################################
# Generated by the 'superfile' Dev Container Feature.
# https://github.com/bugrasan/devcontainers-features
#
# This file is intentionally PARTIAL: superfile loads its built-in defaults
# first and then applies this file on top, so anything not listed here keeps
# upstream's default. Edit it freely - superfile only writes a config file
# when none exists, and this Feature never overwrites an existing one.
#
# Full reference: https://superfile.dev/configure/superfile-config/
##############################################################################

#-- Don't warn about the fields this partial config leaves out.
ignore_missing_fields = true

#-- Dev containers are disposable, so the 24h "is there a newer superfile?"
#-- call to the GitHub API (and its update nag) is just noise. Set the
#-- Feature's 'configureDefaults' option to false to get upstream behaviour.
auto_check_update = false

#-- Nerd Font glyphs. The terminal font lives on the host, not in this
#-- container, so turn this off (Feature option 'nerdfont') if your terminal
#-- isn't using a Nerd Font-patched font and you see tofu boxes.
nerdfont = ${NERDFONT}

#-- cd the shell into superfile's last directory on exit. Needs the shell
#-- wrapper this Feature installs (Feature option 'cdOnQuit').
cd_on_quit = ${CD_ON_QUIT}

###############################################################################
#                                   Plugins                                   #
###############################################################################

#-- Detailed metadata. Requires exiftool; set by the Feature's 'metadata'
#-- option, which defaults to detecting exiftool on PATH.
metadata = ${CFG_METADATA}

#-- Syntax-highlighted preview via bat, "" for the builtin chroma highlighter.
#-- Requires bat; set by the Feature's 'codePreviewer' option, which defaults
#-- to detecting bat on PATH.
code_previewer = ${CFG_CODE_PREVIEWER}

#-- Smart directory jumping. Requires zoxide; set by the Feature's
#-- 'zoxideSupport' option, which defaults to detecting zoxide on PATH.
zoxide_support = ${CFG_ZOXIDE}
SPFCONFIG
chmod 0644 "${home}/.config/superfile/config.toml"
chown "${USERNAME}:${USERNAME}" "${home}/.config"
chown -R "${USERNAME}:${USERNAME}" "${home}/.config/superfile"
# lsp-config (local Feature): Copilot CLI language servers and a short
# Claude Code memory that prefers LSP over grep
mkdir -p "${home}/.copilot"
cat > "${home}/.copilot/lsp-config.json" <<'LSPCONFIG'
{
  "lspServers": {
    "pyright": {
      "command": "pyright-langserver",
      "args": ["--stdio"],
      "fileExtensions": { ".py": "python", ".pyi": "python" }
    },
    "typescript": {
      "command": "typescript-language-server",
      "args": ["--stdio"],
      "fileExtensions": {
        ".ts": "typescript",
        ".tsx": "typescriptreact",
        ".js": "javascript",
        ".jsx": "javascriptreact",
        ".mjs": "javascript",
        ".cjs": "javascript"
      }
    }
  }
}
LSPCONFIG
mkdir -p "${home}/.claude"
cat > "${home}/.claude/CLAUDE.md" <<'CLAUDEMD'
Before code navigation, check whether an LSP server is running. If so, prefer LSP operations (go-to-definition, find-references, hover) over Grep/Read when resolving symbols and types.
CLAUDEMD
chown -R "${USERNAME}" "${home}/.copilot" "${home}/.claude"
# herdr defaults: partial config (no onboarding, no update calls), then the
# herdr-core skill from the installed version's tag for Claude and Copilot
mkdir -p "${home}/.config/herdr"
cat > "${home}/.config/herdr/config.toml" <<HERDRCONFIG
##############################################################################
# Generated by the 'herdr' Dev Container Feature.
# https://github.com/bugrasan/devcontainers-features
#
# This file is intentionally PARTIAL: herdr loads its built-in defaults first
# and then applies this file on top, so anything not listed here keeps
# upstream's default. Edit it freely - this Feature never overwrites an
# existing config file.
#
# Print the full commented default config with: herdr --default-config
# Full reference: https://herdr.dev/docs/config-reference/
##############################################################################

#-- Skip the first-run notification setup. A dev container is rebuilt from
#-- scratch, so the wizard would greet the user on every rebuild.
onboarding = false

[update]
#-- Dev containers are disposable and herdr is installed system-wide when the
#-- image is built, so both background calls to herdr.dev are noise: 'herdr
#-- update', run as this user, cannot replace /usr/local/bin/herdr, and the
#-- agent-detection manifest that ships with the installed binary matches it.
#-- Set the Feature's 'configureDefaults' option to false for upstream
#-- behaviour. 'channel' is deliberately left unset so it keeps its default.
version_check = false
manifest_check = false
HERDRCONFIG
chmod 0644 "${home}/.config/herdr/config.toml"
chown "${USERNAME}:${USERNAME}" "${home}/.config"
chown -R "${USERNAME}:${USERNAME}" "${home}/.config/herdr"
if [ "$(readlink -f "$(command -v hc || true)")" = /usr/local/bin/herdr-core ]; then
    installed="$(/usr/local/bin/herdr-core --version | awk '{ print $2 }')"
    tmpdir="$(mktemp -d)"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
        "https://raw.githubusercontent.com/herdrdev/herdr-core/v${installed}/skills/herdr-core/SKILL.md" \
        -o "${tmpdir}/herdr-core-SKILL.md"
    for agent_home in .claude .copilot; do
        mkdir -p "${home}/${agent_home}/skills/herdr-core"
        install -m 0644 "${tmpdir}/herdr-core-SKILL.md" \
            "${home}/${agent_home}/skills/herdr-core/SKILL.md"
        chown "${USERNAME}:${USERNAME}" "${home}/${agent_home}"
        chown -R "${USERNAME}:${USERNAME}" "${home}/${agent_home}/skills"
    done
    rm -rf "${tmpdir}"
else
    echo "WARNING: 'hc' is not herdr-core in this image - skipping the herdr-core agent skill."
fi
EOF

# Image config of the Feature build: user vscode, home folder as WORKDIR
# (set in layer 4), and bash as the default command.
# hadolint ignore=DL3066
USER ${USERNAME}
CMD ["bash"]
