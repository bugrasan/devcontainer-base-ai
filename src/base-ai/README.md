
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


---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/bugrasan/devcontainer-base-ai/blob/main/src/base-ai/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
