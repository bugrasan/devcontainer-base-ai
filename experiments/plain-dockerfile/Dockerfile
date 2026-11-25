# hadolint global ignore=DL3003,DL3004,DL3008,DL3016,DL3064
# Ignored: sudo (MCR user is vscode), cd (scripts), unpinned apt/npm (newest
# versions by design), ARG USERNAME (not a secret).
FROM mcr.microsoft.com/devcontainers/base:trixie

ARG USERNAME=vscode
ARG USER_UID=1000
ARG USER_GID=${USER_UID}
ENV DEBIAN_FRONTEND=noninteractive

# Same Debian packages as Dockerfile.mcr-trixie. semgrep and watchexec have
# no trixie package, so they are omitted.
RUN apt-get update \
    && apt-get -y upgrade \
    && apt-get install -y --no-install-recommends \
        bat \
        bats \
        bats-assert \
        bats-file \
        ca-certificates \
        curl \
        eza \
        fastfetch \
        fd-find \
        fzf \
        git-delta \
        gnupg2 \
        jq \
        just \
        lazygit \
        mc \
        pass \
        ripgrep \
        shellcheck \
        sudo \
        vim \
        vim-doc \
        vim-scripts \
        xh \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/* /tmp/* /var/tmp/*

# User directories, so bind mounts get the right owner. An empty machine-id
# lets each container bind-mount its own ID (machine-id(5)).
RUN mkdir -p /home/${USERNAME}/.vscode-server/data/User \
    && mkdir -p /home/${USERNAME}/.local/state/herdr-core \
    && mkdir -p /home/${USERNAME}/.cache \
    && mkdir -p /home/${USERNAME}/.ssh \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.vscode-server/ \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.local/ \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.cache/ \
    && chown -R ${USERNAME}:${USERNAME} /home/${USERNAME}/.ssh/ \
    && chmod 700 /home/${USERNAME}/.local/state/herdr-core \
    && chmod 700 /home/${USERNAME}/.ssh \
    && : > /etc/machine-id

USER ${USERNAME}
WORKDIR /home/${USERNAME}

# ~/.local/bin holds uv, claude, specify, herdr and the uv tools. It must be on
# PATH for non-login shells too (docker run image bash -c), and the
# installers only edit rc files. nvm and Python links come after it.
ENV PATH="/home/${USERNAME}/.local/bin:${PATH}"
ENV NVM_DIR=/usr/local/share/nvm \
    NVM_SYMLINK_CURRENT=true \
    PATH="/usr/local/python/current/bin:/usr/local/share/nvm/current/bin:${PATH}"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN <<EOF
#!/bin/bash
set -eo pipefail
curl -fsSL https://astral.sh/uv/install.sh | sh
rm -rf "${HOME}/.cache"/*
EOF

# Feature: otel-collector-contrib (autoStart false, so no start hook),
# copilot-cli and github-cli. curl, ca-certificates, gnupg2, dirmngr,
# apt-transport-https, tar, git: in MCR base (common-utils, git Feature), so
# no apt step and no wget. Each archive is checked against the SHA-256 list
# of its release.
RUN <<EOF
#!/bin/bash
set -eo pipefail
arch=$(dpkg --print-architecture)
tmp=$(mktemp -d)
cd "${tmp}"

# Tag of the latest release (the /latest page redirects to the tag page).
latest() {
    curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$1/releases/latest" | sed 's|.*/||'
}
fetch() { curl -fsSLO --retry 3 "https://github.com/$1/releases/download/$2/$3"; }
# Check file $1 against the hash for it in list $2 (a one-hash file works too).
verify() {
    local want
    want=$(grep -F -- "$1" "$2" | awk 'NR==1 {print $1}' || true)
    [ -n "${want}" ] || want=$(awk 'NR==1 {print $1}' "$2")
    printf '%s  %s\n' "${want}" "$1" | sha256sum -c -
}

# otelcol-contrib: upstream publishes one .sha256 file per archive.
repo=open-telemetry/opentelemetry-collector-releases
tag=$(latest "${repo}")
f=otelcol-contrib_${tag#v}_linux_${arch}.tar.gz
fetch "${repo}" "${tag}" "${f}"
fetch "${repo}" "${tag}" "${f}.sha256"
verify "${f}" "${f}.sha256"
tar -xzf "${f}" otelcol-contrib
sudo install -m 0755 otelcol-contrib /usr/local/bin/otelcol-contrib
sudo install -d /etc/otelcol-contrib
sudo tee /etc/otelcol-contrib/config.yaml >/dev/null <<'YAML'
# OTLP in (localhost only), Azure Application Insights out. The connection
# string comes from the environment when the collector starts.
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: localhost:4317
      http:
        endpoint: localhost:4318

processors:
  batch:

exporters:
  azuremonitor:
    connection_string: "${env:APPLICATIONINSIGHTS_CONNECTION_STRING}"

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
YAML

# copilot-cli: SHA256SUMS.txt is published with each release.
tag=$(latest github/copilot-cli)
f=copilot-linux-$([ "${arch}" = amd64 ] && echo x64 || echo "${arch}").tar.gz
fetch github/copilot-cli "${tag}" "${f}"
fetch github/copilot-cli "${tag}" SHA256SUMS.txt
verify "${f}" SHA256SUMS.txt
tar -xzf "${f}" copilot
sudo install -m 0755 copilot /usr/local/bin/copilot

# github-cli: .deb from the release, checked against its checksums list.
tag=$(latest cli/cli)
f=gh_${tag#v}_linux_${arch}.deb
fetch cli/cli "${tag}" "${f}"
fetch cli/cli "${tag}" "gh_${tag#v}_checksums.txt"
verify "${f}" "gh_${tag#v}_checksums.txt"
sudo dpkg -i "${f}"

cd /
rm -rf "${tmp}"
EOF

# Feature: node 24 via nvm, python os-provided, npm-packages.
# node: curl, ca-certificates, tar, gnupg2, dirmngr, apt-transport-https are
# in MCR base; libatomic1 comes with build-essential (gcc, git Feature).
# python: only python3, pip and venv. Python tools use uv, not pipx; add
# pipx (apt) or use uv tool when something needs it. npm and uv caches
# are cleaned in this layer.
RUN <<EOF
#!/bin/bash
set -eo pipefail
user=$(id -un)

# node: nvm dir writable by the user and the nvm group, as the Feature does.
sudo groupadd -r nvm
sudo usermod -aG nvm "${user}"
sudo mkdir -p "${NVM_DIR}"
sudo chown "${user}:nvm" "${NVM_DIR}"
sudo chmod g+rws "${NVM_DIR}"
umask 0002
# Upstream installer pinned to the newest nvm release tag. It installs
# NODE_VERSION and does not touch the shell profile (PROFILE=/dev/null).
nvm_tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    https://github.com/nvm-sh/nvm/releases/latest | sed 's|.*/||')
export PROFILE=/dev/null NODE_VERSION=24
curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/${nvm_tag}/install.sh" | bash
. "${NVM_DIR}/nvm.sh"
nvm alias default 24
nvm use default
corepack enable
nvm clear-cache
umask 0022
sudo tee -a /etc/bash.bashrc /etc/zsh/zshrc >/dev/null <<'RC'
export NVM_DIR="/usr/local/share/nvm"
[ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
RC
# Login shells reset PATH from /etc/profile; put the image PATH back.
echo "export PATH=/usr/local/python/current/bin:/usr/local/share/nvm/current/bin:\$HOME/.local/bin:\$PATH" \
    | sudo tee /etc/profile.d/00-restore-env.sh >/dev/null
sudo chmod +x /etc/profile.d/00-restore-env.sh

# python: Debian's python3, with the /usr/local/python/current links.
sudo apt-get update
sudo apt-get install -y --no-install-recommends python3 python3-pip python3-venv
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo install -d /usr/local/python/current/bin
for l in python3 python; do
    sudo ln -sf /usr/bin/python3 "/usr/local/python/current/bin/${l}"
done
for l in pydoc3 pydoc; do
    sudo ln -sf /usr/bin/pydoc3 "/usr/local/python/current/bin/${l}"
done
sudo ln -sf /usr/bin/pip3 /usr/bin/pip
# Python tools go to ~/.local/bin; uv must not fetch its own Python.
export UV_PYTHON_DOWNLOADS=never
for t in flake8 autopep8 black yapf mypy pydocstyle pycodestyle bandit \
    pipenv virtualenv pytest pylint; do
    uv tool install "${t}"
done
uv cache clean

# npm-packages
npm install -g editorconfig eslint typescript pyright typescript-language-server
npm cache clean --force
EOF

# Feature: claude-code (native installer, then the LSP plugins) and speckit
# (newest X.Y.Z release tag of github/spec-kit). git is in MCR base.
RUN <<EOF
#!/bin/bash
set -eo pipefail
curl -fsSL https://claude.ai/install.sh | bash -s -- latest
claude plugin marketplace add anthropics/claude-plugins-official --scope user
for p in pyright-lsp typescript-lsp; do
    claude plugin install "${p}@claude-plugins-official" --scope user
done

ver=$(git ls-remote --tags --refs https://github.com/github/spec-kit \
    | sed 's|.*refs/tags/v||' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V | tail -n 1)
UV_PYTHON_DOWNLOADS=never uv tool install specify-cli \
    --from "git+https://github.com/github/spec-kit.git@v${ver}"
uv cache clean
EOF

# Feature: superfile, lsp-config, herdr 3.0.0.
# superfile: release archive checked against its published checksums file.
# herdr and herdr-core: upstream installers, unchanged, into ~/.local/bin.
RUN <<EOF
#!/bin/bash
set -eo pipefail
arch=$(dpkg --print-architecture)
tmp=$(mktemp -d)
cd "${tmp}"

repo=yorukot/superfile
tag=$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
    "https://github.com/${repo}/releases/latest" | sed 's|.*/||')
f=superfile-linux-${tag}-${arch}.tar.gz
sums=superfile-${tag}-checksums.txt
for a in "${f}" "${sums}"; do
    curl -fsSLO --retry 3 "https://github.com/${repo}/releases/download/${tag}/${a}"
done
want=$(grep -F -- "${f}" "${sums}" | awk 'NR==1 {print $1}')
printf '%s  %s\n' "${want}" "${f}" | sha256sum -c -
mkdir x
tar --warning=no-unknown-keyword -xzf "${f}" -C x
sudo install -m 0755 "$(find x -type f -name spf -print -quit)" /usr/local/bin/spf
# superfile calls bat, Debian calls it batcat.
sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
mkdir -p ~/.config/superfile
cat > ~/.config/superfile/config.toml <<'TOML'
# Partial config: superfile fills in the rest from its defaults.
ignore_missing_fields = true
# No update check call to the GitHub API in a throwaway container.
auto_check_update = false
# The terminal font is on the host, so no Nerd Font icons.
nerdfont = false
cd_on_quit = false
metadata = false
code_previewer = "bat"
zoxide_support = false
TOML
cd /
rm -rf "${tmp}"

# lsp-config: Copilot CLI language servers and a Claude Code LSP hint.
mkdir -p ~/.copilot ~/.claude
cat > ~/.copilot/lsp-config.json <<'JSON'
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
JSON
cat > ~/.claude/CLAUDE.md <<'MD'
Before code navigation, check whether an LSP server is running. If so, prefer LSP operations (go-to-definition, find-references, hover) over Grep/Read when resolving symbols and types.
MD

# herdr TUI and herdr-core (hc), then config, completions and the skill.
curl -fsSL https://herdr.dev/install.sh | sh
curl -fsSL https://releases.herdr.dev/core/install.sh | sh
mkdir -p ~/.config/herdr
cat > ~/.config/herdr/config.toml <<'TOML'
# Partial config: herdr fills in the rest from its defaults.
# No first-run wizard on every rebuild.
onboarding = false

[update]
# No background calls to herdr.dev; a rebuild is the update path.
version_check = false
manifest_check = false
TOML
sudo install -d /usr/share/bash-completion/completions \
    /usr/local/share/zsh/site-functions
herdr completion bash | sudo tee /usr/share/bash-completion/completions/herdr >/dev/null
herdr completion zsh | sudo tee /usr/local/share/zsh/site-functions/_herdr >/dev/null
core_ver=$(herdr-core --version | awk '{ print $2 }')
for h in .claude .copilot; do
    mkdir -p "${HOME}/${h}/skills/herdr-core"
    curl -fsSL --retry 3 \
        "https://raw.githubusercontent.com/herdrdev/herdr-core/v${core_ver}/skills/herdr-core/SKILL.md" \
        -o "${HOME}/${h}/skills/herdr-core/SKILL.md"
done
EOF

ENV PYTHON_PATH=/usr/local/python/current \
    ENABLE_LSP_TOOL=1

SHELL ["/bin/sh", "-c"]
