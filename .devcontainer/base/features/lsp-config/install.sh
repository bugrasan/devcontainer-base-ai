#!/bin/bash

# exit on error
set -e

# variables provided by devcontainer-feature (booleans arrive as "true"/"false")
COPILOT_LSP_CONFIG="${COPILOTLSPCONFIG:-true}"
CLAUDE_LSP_BIAS="${CLAUDELSPBIAS:-true}"

# install.sh always runs as root; the config belongs to the container's user.
# https://containers.dev/implementors/features#user-env-var
TARGET_USER="${_REMOTE_USER:-root}"
TARGET_HOME="${_REMOTE_USER_HOME:-/root}"

# GitHub Copilot CLI reads ~/.copilot/lsp-config.json (user scope). 'command' must
# be on PATH at runtime - pyright-langserver + typescript-language-server come from
# the npm-packages Feature. gopls is intentionally omitted (no Go toolchain here).
if [ "${COPILOT_LSP_CONFIG}" = "true" ]; then
    mkdir -p "${TARGET_HOME}/.copilot"
    cat > "${TARGET_HOME}/.copilot/lsp-config.json" <<'EOF'
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
EOF
fi

# Claude Code reads ~/.claude/CLAUDE.md as user memory - a soft bias, not a switch.
if [ "${CLAUDE_LSP_BIAS}" = "true" ]; then
    mkdir -p "${TARGET_HOME}/.claude"
    cat > "${TARGET_HOME}/.claude/CLAUDE.md" <<'EOF'
Before code navigation, check whether an LSP server is running. If so, prefer LSP operations (go-to-definition, find-references, hover) over Grep/Read when resolving symbols and types.
EOF
fi

# Hand ownership of anything we created to the remote user (we wrote it as root).
if [ "${TARGET_USER}" != "root" ]; then
    chown -R "${TARGET_USER}" "${TARGET_HOME}/.copilot" "${TARGET_HOME}/.claude" 2>/dev/null || true
fi

echo 'Done!'
