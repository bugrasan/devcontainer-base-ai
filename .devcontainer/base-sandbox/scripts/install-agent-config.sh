#!/bin/bash
# Agent-side LSP configuration - the 'lsp-config' Feature of the :base image,
# as plain files.
#
# Only the wiring lives here. The language-server binaries come from the global
# npm packages (pyright-langserver, typescript-language-server), and Claude
# Code's own LSP tool is switched on by ENABLE_LSP_TOOL=1 in the Dockerfile.
set -euo pipefail
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

TARGET_USER="${1:?target user required}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "${TARGET_USER}")"

# GitHub Copilot CLI reads ~/.copilot/lsp-config.json at user scope. 'command'
# must resolve at run time. gopls is left out: no Go toolchain in this image.
mkdir -p "${TARGET_HOME}/.copilot"
cat > "${TARGET_HOME}/.copilot/lsp-config.json" <<'CONFIG'
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
CONFIG

# Claude Code reads ~/.claude/CLAUDE.md as user memory - a bias, not a switch.
# Appended, not overwritten: the herdr install may already have written here.
mkdir -p "${TARGET_HOME}/.claude"
cat >> "${TARGET_HOME}/.claude/CLAUDE.md" <<'MEMORY'
Before code navigation, check whether an LSP server is running. If so, prefer LSP operations (go-to-definition, find-references, hover) over Grep/Read when resolving symbols and types.
MEMORY

chown -R "${TARGET_USER}:${TARGET_GROUP}" "${TARGET_HOME}/.copilot" "${TARGET_HOME}/.claude"
log "agent LSP configuration written"
