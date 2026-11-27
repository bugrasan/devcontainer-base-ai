#!/bin/bash
# Smoke test for the :base image. Runs inside the container as the remote
# user; publish-base-image.yml mounts it and lsp-check.py read-only into one
# folder and runs it with bash. Arg 1 overrides the lsp-check.py path.
set -euo pipefail
LSP_CHECK="${1:-$(dirname "$0")/lsp-check.py}"

# Language servers wired by the lsp-config Feature, by server ID. Each one
# is a Copilot CLI server "<id>" and a Claude Code plugin "<id>-lsp".
LSP_SERVERS=(bash yaml json html css dockerfile markdown toml typescript)
# Plus pyright: Copilot from base-ai-lsp, Claude from the official
# marketplace (claude-code Feature).
COPILOT_SERVERS=("${LSP_SERVERS[@]}" pyright)
CLAUDE_PLUGINS=("${LSP_SERVERS[@]/%/-lsp@base-ai-lsp}"
    pyright-lsp@claude-plugins-official)
# Must not be enabled: it runs typescript-language-server, which fails with
# TypeScript 7, and would compete with typescript-lsp@base-ai-lsp.
CLAUDE_UNWANTED=typescript-lsp@claude-plugins-official
# Binaries from the npm-packages and lsp-servers Features.
LSP_BINARIES=(bash-language-server yaml-language-server
    vscode-json-language-server vscode-html-language-server
    vscode-css-language-server docker-langserver marksman taplo)

# Print each argument that is not a line on stdin.
missing() {
    local have item
    have="$(cat)"
    for item in "$@"; do
        grep -qxF -- "${item}" <<< "${have}" || printf '%s ' "${item}"
    done
}

echo "=== Smoke Test ==="
command -v node || exit 1
echo "✓ node found"
node --version
command -v python3 || exit 1
echo "✓ python3 found"
python3 --version
command -v gh || exit 1
echo "✓ gh found"
gh --version
command -v copilot || exit 1
echo "✓ copilot found"
copilot --version
command -v uv || exit 1
echo "✓ uv found"
uv --version
command -v eslint || exit 1
echo "✓ eslint found"
command -v tsc || exit 1
echo "✓ tsc found"
command -v pyright-langserver || exit 1
echo "✓ pyright-langserver found"
command -v typescript-language-server || exit 1
echo "✓ typescript-language-server found"
for bin in "${LSP_BINARIES[@]}"; do
    command -v "${bin}" || exit 1
    echo "✓ ${bin} found"
done
marksman --version
taplo --version
test -f "$HOME/.claude/CLAUDE.md" || exit 1
echo "✓ claude LSP bias baked in"
command -v claude || exit 1
echo "✓ claude found"
claude --version

miss="$(copilot lsp list --json | jq -r '.[].id' \
    | missing "${COPILOT_SERVERS[@]}")"
if [ -n "${miss}" ]; then
    echo "✗ copilot language servers missing: ${miss}"
    exit 1
fi
echo "✓ copilot language servers configured: ${COPILOT_SERVERS[*]}"
claude_enabled="$(claude plugin list --json \
    | jq -r '.[] | select(.enabled) | .id')"
miss="$(missing "${CLAUDE_PLUGINS[@]}" <<< "${claude_enabled}")"
if [ -n "${miss}" ]; then
    echo "✗ claude LSP plugins missing or disabled: ${miss}"
    exit 1
fi
echo "✓ claude LSP plugins installed and enabled: ${CLAUDE_PLUGINS[*]}"
if grep -qxF "${CLAUDE_UNWANTED}" <<< "${claude_enabled}"; then
    echo "✗ claude plugin enabled but broken with TypeScript 7: ${CLAUDE_UNWANTED}"
    exit 1
fi
echo "✓ claude plugin not enabled: ${CLAUDE_UNWANTED}"
# Start every server both agents configure, with their command and args.
python3 "${LSP_CHECK}" || exit 1
echo "✓ language servers answer (lsp-check.py)"

command -v herdr || exit 1
echo "✓ herdr found"
herdr --version
command -v herdr-core || exit 1
echo "✓ herdr-core found"
herdr-core --version
test -f "$HOME/.claude/skills/herdr-core/SKILL.md" || exit 1
test -f "$HOME/.copilot/skills/herdr-core/SKILL.md" || exit 1
echo "✓ herdr-core skill baked in for claude and copilot"
test -O "$HOME/.local/state" && test -O "$HOME/.local/state/herdr-core" || exit 1
test "$(stat -c %a "$HOME/.local/state/herdr-core")" = 700 || exit 1
echo "✓ ~/.local/state/herdr-core owned by the user, mode 700 (herdr-core state mount)"
test -f /etc/machine-id && ! test -s /etc/machine-id || exit 1
echo "✓ /etc/machine-id is an empty file"
# command -v sshd || exit 1
# echo "✓ sshd found"
# grep -qx "Port 2222" /etc/ssh/sshd_config || exit 1
# echo "✓ sshd configured on port 2222"
# test -x /etc/init.d/ssh || exit 1
# echo "✓ sshd init script found"
echo "✓ All tools verified"
