# Base AI Dev Container — Notes

- Requires `~/.ssh/id_ed25519.pub` on the host (bind-mounted for the `sshd` feature's `authorized_keys`).
- SSH is forwarded on the `sshdPort` option you chose (default `2222`).
- A `.env` file is auto-created at the workspace root on first launch — add secrets there.
- Reopen in container, then rebuild whenever `.devcontainer/devcontainer.json` changes.

## LSP code intelligence

`ENABLE_LSP_TOOL=1` is set so AI agents use language servers (go-to-definition,
find-references, hover, diagnostics) instead of grep/read. Wired for all three
harnesses baked into the `:base` image:

- **Claude Code** — the `claude-code` Feature installs the `pyright-lsp` +
  `typescript-lsp` plugins at user scope and sets `ENABLE_LSP_TOOL=1`.
- **GitHub Copilot CLI** — user-scope `~/.copilot/lsp-config.json` (written by
  the local `lsp-config` Feature) wires the Python + TypeScript servers.
- **VS Code Copilot** — the built-in `find_symbol` tool reads from Pylance
  (Python extension) and VS Code's built-in TypeScript features.

Language servers: `pyright-langserver` + `typescript-language-server` (from the
`npm-packages` Feature). Go is **not** included; add a Go toolchain + the
`gopls-lsp` plugin if you need it.
