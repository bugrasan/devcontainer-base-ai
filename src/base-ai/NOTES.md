# Base AI Dev Container — Notes

- Requires `~/.ssh/id_ed25519.pub` on the host (bind-mounted for the `sshd` feature's `authorized_keys`).
- sshd listens on the port set by the `sshdPort` option (default `2222`), and VS Code forwards it
- A `.env` file is auto-created at the workspace root on first launch — add secrets there.
- Reopen in container, then rebuild whenever `.devcontainer/devcontainer.json` changes.

## herdr-core identity

On each launch, `initializeCommand` sets up the herdr-core identity on the host.

- `.devcontainer/herdr-machine-id` is mounted read-only as `/etc/machine-id`.
  It holds a `uuidgen` UUID without dashes in lowercase.
  A launch writes it if it is missing or not 32 hex characters, and `.devcontainer/.gitignore` excludes it.
- `.devcontainer/herdr-labels` holds `herdr-machine-id=<machine-id>`, which `runArgs` passes to Docker as a container label.
  `.devcontainer/.gitignore` excludes it too.
  To find a project's container, run `docker ps --filter "label=$(cat .devcontainer/herdr-labels)"` in the project folder.
- `~/.config/herdr-core/container/<folder>-<devcontainerId>/` on the host is mounted as `~/.local/state/herdr-core`, the herdr-core state directory.
  It holds terminal output, which may contain secrets, so it has mode 700 and stays outside the project.

`<devcontainerId>` is a 52-character hash of the project folder path and the `devcontainer.json` path.
It stays the same across rebuilds and changes when you move or rename the project folder.

With the machine-id and the state folder on the host, a recreated container should keep the herdr-core identity ([herdr-core issue #304](https://github.com/herdrdev/herdr-core/issues/304)).
Don't copy `.devcontainer/herdr-machine-id` to another project, or both projects share one machine-id.
To start over, delete the id file and the state folder, and the next launch writes a new id.
When you delete a project, delete its state folder too.
When you move or rename the project folder, the next container gets a new, empty state folder, while the machine-id and the label stay the same.
To keep the state, replace the new folder with the old one while the container is stopped.

Docker gives each new container a random name, so an `hc` machine entry can't point at a fixed name.
Instead, its `--via` command can look the container up by the label on each connection (untested):

```bash
hc machine add --name <name> --via 'docker exec -i $(docker ps -q --filter label=herdr-machine-id=<machine-id>) sh -c'
```

The host needs `uuidgen`; on Ubuntu, the `uuid-runtime` package provides it.
Without it, the launch fails until you install it.

The state folder is under `~/.config/herdr-core/`, so a Docker VM, such as Docker Desktop, colima, or Podman machine, must share that folder.
After you update the template, run `docker pull ghcr.io/bugrasan/devcontainer-base-ai/base:latest`, because an older cached image may lack `~/.local/state/herdr-core`.

## LSP code intelligence

`ENABLE_LSP_TOOL=1` is set so AI agents use language servers (go-to-definition,
find-references, hover, diagnostics) instead of grep/read. Wired for all three
harnesses baked into the `:base` image:

- **Claude Code** — the `claude-code` Feature installs the `pyright-lsp` +
  `typescript-lsp` plugins at user scope and sets `ENABLE_LSP_TOOL=1`.
- **GitHub Copilot CLI** — user-scope `~/.copilot/lsp-config.json` (written by
  the local `lsp-config` Feature) wires the Python + TypeScript servers.
- **VS Code Copilot** — the built-in `usages` tool (`#usages`, since v1.99;
  *not* `find_symbol`, which is a Visual Studio 2026 tool) reads from Pylance
  (Python extension) and VS Code's built-in TypeScript features.

Language servers: `pyright-langserver` + `typescript-language-server` (from the
`npm-packages` Feature). Go is **not** included; add a Go toolchain + the
`gopls-lsp` plugin if you need it.

## OpenTelemetry Collector (not auto-started)

The `otel-collector-contrib` Feature is baked into the `:base` image with
`autoStart: false`: only the `otelcol-contrib` binary and its default OTLP →
Azure Application Insights config (`/etc/otelcol-contrib/config.yaml`) are
installed — nothing runs and nothing listens on 4317/4318 at container start.
Start it manually when needed:

```bash
# only needed for the default config (resolved at collector startup, never baked in)
export APPLICATIONINSIGHTS_CONNECTION_STRING=...
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

## Copilot CLI auto-update

The `copilot-cli` Feature runs an online update check on every container start.
It's disabled here by removing the Feature's flag file
(`/etc/devcontainer-copilot-cli/auto-update`) in `postCreateCommand`, so you
still get the latest `copilot` at each weekly base-image rebuild without the
per-start network check. Delete that `postCreateCommand` entry to restore it.
