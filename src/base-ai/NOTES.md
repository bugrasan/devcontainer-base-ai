# Base AI Dev Container — Notes

- Requires `~/.ssh/id_ed25519.pub` on the host (bind-mounted for the `sshd` feature's `authorized_keys`).
- SSH is forwarded on the `sshdPort` option you chose (default `2222`).
- A `.env` file is auto-created at the workspace root on first launch — add secrets there.
- Reopen in container, then rebuild whenever `.devcontainer/devcontainer.json` changes.
