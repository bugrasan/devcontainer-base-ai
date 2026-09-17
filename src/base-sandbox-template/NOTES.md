# Base Sandbox Dev Container — Notes

## What this is

A dev container for running coding agents with broad autonomy, built so that
"the agent can run anything" stays a statement about the container and not
about your laptop. It consumes the pre-built
`ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox:latest` image, which bakes
the whole stack in a plain Dockerfile — **no Dev Container Features**.

## Before the first start

- `~/.ssh/id_ed25519.pub` must exist on the host: it is bind-mounted read-only
  and becomes the container's `authorized_keys`. The **private** key is never
  mounted and the host SSH agent is never forwarded
- a `.env` file is created at the workspace root on first launch — put secrets
  there, it is passed to the container with `--env-file`
- rebuild the container whenever `.devcontainer/devcontainer.json` changes

## What is different from the `base-ai` template

| | `base-ai` | `base-sandbox` |
|---|---|---|
| image built from | Dockerfile + 12 Features | one Dockerfile |
| `sudo` | passwordless for `vscode` | not installed |
| SSH host keys | baked into the image | generated on first start |
| Node.js | `node` Feature | upstream tarball, v24 |
| Python / pip / pipx | `python` Feature | from the OS |
| Linux capabilities | all defaults | all dropped |
| `pi-dev` | included | not included |

## SSH

`sshd` runs **as the `vscode` user**, not as root — the image has no `sudo` and
the container drops every capability, so nothing here can write `/etc/ssh` or
switch user. It only ever authenticates the one account it already runs as,
which needs no privilege at all.

- host keys are generated on first start into `~/.ssh/host_keys/` and then reused
  for the life of that container. A rebuild gets fresh keys, so clear the stale
  entry from your `known_hosts` after one
- the image ships **no** host keys. A key baked into a published image is the
  same key for everyone who pulls it
- the port comes from the `sshdPort` template option and is read at container
  start, so changing it needs a restart, not an image rebuild
- set the `startSshd` option to `false` to leave the port closed

```bash
ssh -p 2222 vscode@localhost
```

## Hardening

Two of four layers are switched on here. The full rationale, what each layer
costs, and how to enable the other two is in
[docs/hardening.md](https://github.com/bugrasan/devcontainer-base-ai/blob/main/docs/hardening.md).

- **Layer 1 — no handles back to the host.** `remoteEnv` empties the SSH agent,
  GPG agent, browser, VS Code IPC and git-credential variables; the image clears
  them again in login shells, interactive shells and `bash -c`;
  `postStartCommand` deletes the matching sockets from `/tmp` and keeps sweeping
  for as long as the container runs
- **Layer 2 — no privilege to take.** No `sudo` in the image, `--cap-drop=ALL`
  and `--security-opt=no-new-privileges` in `runArgs`
- **Layer 3 — Docker socket proxy** and **Layer 4 — outbound egress allowlist**
  are documented but not enabled: layer 3 needs a `docker-compose.yml` instead
  of a plain `image`, and layer 4 needs `NET_ADMIN`/`NET_RAW` added back

The `code` CLI does not work inside the container. That is layer 1 working:
the socket it needs is the one that executes commands in your host VS Code.

There is no `sudo`, and the image ships no setuid binaries either, so there is
no path from the container's user to root.

### What breaks

- `ping` and `traceroute` — they need `NET_RAW`, which layer 2 drops
- `apt-get install` — there is no `sudo`. Add packages to the image instead, or
  use `uv`, `pipx` and `npm -g`, all of which work without root
- anything expecting to write outside `$HOME` and the workspace

## LSP code intelligence

`ENABLE_LSP_TOOL=1` is set, so the agents use language servers instead of
grep/read:

- **Claude Code** — the `pyright-lsp` and `typescript-lsp` plugins, installed at
  user scope in the image
- **GitHub Copilot CLI** — `~/.copilot/lsp-config.json`
- **VS Code Copilot** — the built-in `usages` tool (`#usages`), backed by
  Pylance and the built-in TypeScript features

Servers: `pyright-langserver` and `typescript-language-server`, installed
globally with npm. Go is not included.

## OpenTelemetry Collector (not auto-started)

The binary and a default OTLP → Azure Application Insights config
(`/etc/otelcol-contrib/config.yaml`) are in the image. Nothing runs and nothing
listens on 4317/4318 until you start it:

```bash
export APPLICATIONINSIGHTS_CONNECTION_STRING=...
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

## Installing more tools

There is no `sudo`, by design. Without root you can still:

```bash
uv tool install <cli>        # Python CLIs
pipx install <cli>           # ditto, OS Python
npm install -g <pkg>         # goes to ~/.npm-global, already on PATH
```

Anything that genuinely needs root belongs in the image — open an issue or add
a `RUN` line to `.devcontainer/base-sandbox/Dockerfile.trixie`.
