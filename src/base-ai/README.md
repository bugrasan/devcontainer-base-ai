
# Base AI Dev Container (base-ai)

One-size-fits-all Debian trixie dev container for AI/ML development: node, python, github-cli, copilot-cli, sshd, and a curated set of CLI tools (bat, eza, fzf, ripgrep, lazygit, jq, and more).

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| sshdPort | Port sshd listens on inside the container; VS Code forwards it to the host. | string | 2222 |

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
- `~/.config/herdr-core/container/<folder>-<devcontainerId>/` on the host is mounted as `~/.local/state/herdr-core`, the herdr-core state directory.
  It holds terminal output, which may contain secrets, so it has mode 700 and stays outside the project.

`<devcontainerId>` is a 52-character hash of the project folder path and the `devcontainer.json` path.
It stays the same across rebuilds and changes when you move or rename the project folder.

With the machine-id and the state folder on the host, a recreated container should keep the herdr-core identity ([herdr-core issue #304](https://github.com/herdrdev/herdr-core/issues/304)).
Don't copy `.devcontainer/herdr-machine-id` to another project, or both projects share one machine-id.
To start over, delete the id file and the state folder, and the next launch writes a new id.
Deleting only the id file keeps the old state folder, because its name uses `<devcontainerId>`, not the machine-id.
When you delete a project, delete its state folder too.
When you move or rename the project folder, the next container gets a new, empty state folder, while the machine-id stays the same.
To keep the state, replace the new folder with the old one while the container is stopped.

Docker gives each new container a random name.
To find a project's container, use the label the devcontainer CLI sets (untested with the VS Code extension): `docker ps --filter "label=devcontainer.local_folder=<project path>"`.
An `hc` machine entry can't point at a fixed name, but its `--via` command can look the container up by that label on each connection (untested):

```bash
hc machine add --name <name> --via 'docker exec -i $(docker ps -q --filter "label=devcontainer.local_folder=<project path>") sh -c'
```

The inner double quotes keep a project path with spaces together; a path with a single quote doesn't work in this form.
If the project has more than one dev container config, add `--filter "label=devcontainer.config_file=<path to devcontainer.json>"` to both commands, so only one container matches.

The host needs `uuidgen`; on Ubuntu, the `uuid-runtime` package provides it.
Without it, the launch fails until you install it.

The state folder is under `~/.config/herdr-core/`, so a Docker VM, such as Docker Desktop, colima, or Podman machine, must share that folder.
After you update the template, run `docker pull ghcr.io/bugrasan/devcontainer-base-ai/base:latest`, because an older cached image may lack `~/.local/state/herdr-core`.

## LSP code intelligence

`ENABLE_LSP_TOOL=1` is set, so AI agents use language servers (go-to-definition, find-references, hover, diagnostics) instead of grep/read.
The `:base` image ships these servers:

| Server ID | Command | File extensions |
|---|---|---|
| `bash` | `bash-language-server start` | `.sh`, `.bash` |
| `yaml` | `yaml-language-server --stdio` | `.yaml`, `.yml` |
| `json` | `vscode-json-language-server --stdio` | `.json`, `.jsonc` |
| `html` | `vscode-html-language-server --stdio` | `.html`, `.htm` |
| `css` | `vscode-css-language-server --stdio` | `.css`, `.scss`, `.less` |
| `dockerfile` | `docker-langserver --stdio` | `.dockerfile` only; a file named `Dockerfile` doesn't match |
| `markdown` | `marksman server` | `.md`, `.markdown` |
| `toml` | `taplo lsp stdio` | `.toml` |
| `pyright` | `pyright-langserver --stdio` | `.py`, `.pyi` |
| `typescript` | `tsc --lsp --stdio` (TypeScript 7) | `.ts`, `.tsx`, `.mts`, `.cts`, `.js`, `.jsx`, `.mjs`, `.cjs` |

The `npm-packages` Feature installs the npm servers, and the `lsp-servers` Feature installs `marksman` and `taplo` into `~/.local/bin`.
The bash server uses `shellcheck` for diagnostics and `shfmt` for formatting; both are installed.
The global `typescript` package is TypeScript 7, which brings its own language server (`tsc --lsp --stdio`) and no `lib/tsserver.js`.
The image doesn't install `typescript-language-server`, because it needs `lib/tsserver.js` ([typescript-language-server#1110](https://github.com/typescript-language-server/typescript-language-server/issues/1110)); a project with a local TypeScript 6 or older can install it locally.
`vscode-eslint-language-server` is installed but not wired: Copilot CLI starts one server per file extension, so it never ran next to `typescript`, and it has no symbols and needs VS Code settings.
jdtls (Java, with `openjdk-25-jdk-headless`), terraform-ls, and LemMinx (XML) are available, commented out, in `.devcontainer/base/features/lsp-servers` of the [devcontainer-base-ai](https://github.com/bugrasan/devcontainer-base-ai) repo.
Go is not included.

How each agent gets the servers:

- **Claude Code** – user-scope plugins `<id>-lsp@base-ai-lsp` for every server except pyright.
  pyright comes from `pyright-lsp@claude-plugins-official`, installed by the `claude-code` Feature.
  The image doesn't install `typescript-lsp@claude-plugins-official`, because it runs `typescript-language-server`.
- **GitHub Copilot CLI** – user-scope plugins `<id>-lsp@base-ai-lsp` for every server, including pyright, because Copilot CLI can't add the `claude-plugins-official` marketplace.
- **VS Code** – VS Code doesn't use the CLI plugins; its language features come from extensions with their own servers.
  JSON, HTML, CSS, Markdown, and TypeScript are built in, the `node` and `python` Features add ESLint and Pylance, and this Template adds YAML, Bash, Docker, and TOML extensions.
  The built-in `usages` tool (`#usages`, since v1.99; not `find_symbol`, which is a Visual Studio 2026 tool) reads from these extensions.
  The `anthropic.claude-code` extension runs Claude Code, so the Claude Code plugins should apply there too (unverified).

### The `base-ai-lsp` plugin marketplace

The `lsp-config` Feature generates a local plugin marketplace at `/usr/local/share/base-ai-lsp`, with one plugin per server.
The folder is owned by root and read-only for the user.
Each plugin holds two manifests: `.claude-plugin/plugin.json` for Claude Code and `.github/plugin/plugin.json` for Copilot CLI.
Copilot CLI loads the plugins from that folder; Claude Code copies them to `~/.claude/plugins/cache`.
No third-party marketplace is involved.
Run `copilot lsp list` or `claude plugin list` to see them.

- A bind mount of a host `~/.claude` (commented out in `mounts`) hides the plugins baked into the image's `~/.claude`.
  To get them back, run `claude plugin marketplace add /usr/local/share/base-ai-lsp --scope user`, then `claude plugin install <id>-lsp@base-ai-lsp --scope user` for each server; this writes to the mounted host folder.
- A project can override or turn off a Copilot CLI server in `.github/lsp.json`.
  For example, `{"lspServers": {"yaml": {"disabled": true}}}` removes the yaml server for that project.

### YAML schemas

`yaml-language-server` can download the SchemaStore catalog from `www.schemastore.org`, then each matching schema on demand.
Schemas add validation, completion, and hover for known files, such as GitHub workflows; without them, YAML still gets syntax checks and symbols.
The server applies its settings, and starts the download, only when the client sends `workspace/didChangeConfiguration`.

- Copilot CLI 1.0.116 doesn't send it, so it gets no download and no schema validation (tested).
- Claude Code sends its `settings` field that way, so the download likely runs there (unverified).

For offline or sandboxed containers, see the comment at the yaml row in `.devcontainer/base/features/lsp-config/install.sh`.

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


---

_Note: This file was auto-generated from the [devcontainer-template.json](https://github.com/bugrasan/devcontainer-base-ai/blob/main/src/base-ai/devcontainer-template.json).  Add additional notes to a `NOTES.md`._
