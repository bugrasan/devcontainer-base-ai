
# Base AI Dev Container (base-ai)

One-size-fits-all Debian trixie dev container for AI/ML development: node, python, github-cli, copilot-cli, sshd, and a curated set of CLI tools (bat, eza, fzf, ripgrep, lazygit, jq, and more).

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| sshdPort | Port to expose the sshd feature on (must match across forwardPorts, portsAttributes, and containerEnv.SSHD_PORT). | string | 2222 |

# Base AI Dev Container — Notes

- Requires `~/.ssh/id_ed25519.pub` on the host (bind-mounted for the `sshd` feature's `authorized_keys`).
- SSH is forwarded on the `sshdPort` option you chose (default `2222`).
- A `.env` file is auto-created at the workspace root on first launch — add secrets there.
- Reopen in container, then rebuild whenever `.devcontainer/devcontainer.json` changes.

## LSP code intelligence

`ENABLE_LSP_TOOL=1` is set so AI agents use language servers (go-to-definition,
find-references, hover, diagnostics) instead of grep/read. Wired for all three
harnesses baked into the `:base` image:

- **Claude Code** — the `claude-code` Feature installs the `pyright-lsp`,
  `typescript-lsp`, and `gopls-lsp` plugins at user scope; `ENABLE_LSP_TOOL=1`
  turns the tool on.
- **GitHub Copilot CLI** — user-scope `~/.copilot/lsp-config.json` wires the
  Python + TypeScript servers.
- **VS Code Copilot** — the built-in `find_symbol` tool reads from Pylance
  (Python extension) and VS Code's built-in TypeScript features.

Language servers: `pyright-langserver` + `typescript-language-server` (from the
`npm-packages` Feature). `gopls` is **not** baked in, so `gopls-lsp` stays
dormant until you add a Go toolchain.


---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/bugrasan/devcontainer-base-ai/blob/main/src/base-ai/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
