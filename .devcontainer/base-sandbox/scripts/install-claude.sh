#!/bin/bash
# Claude Code via its native installer, plus the LSP code-intelligence plugins.
#
# claude.ai/install.sh is a self-contained native binary installer with no
# npm/node dependency, and it installs under the invoking user's $HOME, so it
# runs as the target user. Installed last in the Dockerfile on purpose: it
# tracks the 'latest' channel and changes more often than anything below it,
# and a Docker layer invalidates everything after it.
set -euo pipefail
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

TARGET_USER="${1:?target user required}"
CLAUDE_VERSION="${2:-latest}"
LSP_MARKETPLACES="${3:-anthropics/claude-plugins-official}"
LSP_PLUGINS="${4:-pyright-lsp@claude-plugins-official typescript-lsp@claude-plugins-official}"

TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"

log "installing Claude Code (${CLAUDE_VERSION})"
as_user "${TARGET_USER}" "curl -fsSL https://claude.ai/install.sh | bash -s -- ${CLAUDE_VERSION}"

# ~/.local/bin is not on PATH for every shell shape, and the installer itself
# warns about exactly that. A symlink in /usr/local/bin resolves everywhere.
[ -x "${TARGET_HOME}/.local/bin/claude" ] || die "the Claude Code installer left no ${TARGET_HOME}/.local/bin/claude."
ln -sf "${TARGET_HOME}/.local/bin/claude" /usr/local/bin/claude

# A fresh install has NO marketplaces registered, so each one must be added
# before its plugins can resolve.
#
# NON-FATAL by design: a plugin only wires the connection to a language server.
# The server binary (pyright-langserver, typescript-language-server) comes from
# the global npm packages, and a transient network error here must not fail an
# image build whose other 20 tools are fine.
if [ -n "${LSP_PLUGINS}" ]; then
    for repo in ${LSP_MARKETPLACES}; do
        log "adding Claude Code plugin marketplace: ${repo}"
        as_user "${TARGET_USER}" "claude plugin marketplace add ${repo} --scope user" ||
            warn "could not add marketplace '${repo}' (continuing)"
    done
    for plugin in ${LSP_PLUGINS}; do
        log "installing Claude Code LSP plugin: ${plugin}"
        as_user "${TARGET_USER}" "claude plugin install ${plugin} --scope user" ||
            warn "could not install plugin '${plugin}' - install it later with 'claude plugin install ${plugin}'"
    done
fi
log "Claude Code installed"
