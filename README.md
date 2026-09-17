# devcontainer-base-ai

Base devcontainer configuration for AI/ML development projects, in two flavours.

**`base-ai`** — the full kitchen sink, built from Dev Container Features:

1. **[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json)** — one-size-fits-all dev container for *this* repo, copyable into other projects.
2. **[src/base-ai/](src/base-ai/)** — same config packaged as a [Dev Container Template](https://containers.dev/implementors/templates/), published to GHCR (not on the public index).
3. **[.devcontainer/base/](.devcontainer/base/)** — bakes `Dockerfile.mcr-trixie` + Features into a pre-built image, rebuilt weekly, consumed by (1) via its `image` property.

**`base-sandbox`** — the same stack, hardened for coding agents and built from a single Dockerfile with **no Features**:

4. **[.devcontainer/base-sandbox/](.devcontainer/base-sandbox/)** — one `Dockerfile.trixie` plus its installer scripts, rebuilt weekly, published as `:base-sandbox`.
5. **[src/base-sandbox-template/](src/base-sandbox-template/)** — the matching Template, which consumes that image and adds the runtime hardening.

No `sudo`, no SSH host keys in the image, no host sockets or credentials passed in — see **[docs/hardening.md](docs/hardening.md)**.

## Usage

Add this repo as a remote, then copy over the devcontainer config:

```bash
git remote add devcontainer-upstream https://<HOST>/<USER>/devcontainer-base-ai.git
git fetch devcontainer-upstream
git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json
git commit -m "Add devcontainer.json from devcontainer-base-ai"
```

To sync later improvements, `git fetch` again then either replace the file
outright (`git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json`),
cherry-pick a specific commit (`git cherry-pick <hash>`), or apply hunks
interactively (`git checkout -p devcontainer-upstream/main -- .devcontainer/devcontainer.json`).
See [Quick Reference](#quick-reference) for the full command list.

## Dev Container Template: `base-ai`

[src/base-ai/](src/base-ai/) packages the same configuration as a
[Dev Container Template](https://containers.dev/implementors/templates/) and is
published as an OCI artifact by
[.github/workflows/publish-templates.yml](.github/workflows/publish-templates.yml)
(on push to `main` touching `src/**`) via the
[`devcontainers/action`](https://github.com/devcontainers/action) GitHub Action.

- **Template reference:** `ghcr.io/bugrasan/devcontainer-base-ai/base-ai`
- **Not on the public [containers.dev](https://containers.dev/templates) index** — it won't appear in the VS Code/Codespaces template picker; apply it directly:

  ```bash
  # :0 is the floating major tag (currently 0.1.1); pin an exact version with :0.1.1 if you prefer
  devcontainer templates apply -w /path/to/project -t ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0
  ```

> **One-time setup:** GHCR packages default to private. Make the published
> packages public once via `github.com/users/bugrasan/packages` → package →
> **Settings → Danger Zone → Change visibility**: the `base` and `base-sandbox`
> images and the `base-ai` and `base-sandbox-template` templates (required for
> anonymous pull/apply), plus the `devcontainer-base-ai` collection metadata
> package (optional). This can't be automated with the default `GITHUB_TOKEN`.

## The `:base` Image

[.devcontainer/base/devcontainer.json](.devcontainer/base/devcontainer.json) is
a build-only definition (not meant to be opened in VS Code) that builds
[Dockerfile.mcr-trixie](.devcontainer/base/Dockerfile.mcr-trixie) plus the same
Features as the root devcontainer.json (`common-utils`, `sshd`, `node`,
`python`, `github-cli`, `copilot-cli`, plus the local `npm-packages` Feature
and the published `claude-code`/`pi-dev`/`speckit`/`otel-collector-contrib`/
`superfile`/`herdr` Features), baking them all into:

```
ghcr.io/bugrasan/devcontainer-base-ai/base:latest
```

[.github/workflows/publish-base-image.yml](.github/workflows/publish-base-image.yml)
builds and pushes this multi-arch image via
[`devcontainers/ci`](https://github.com/devcontainers/ci) on pushes to `main`
touching `.devcontainer/base/**`, and on a schedule (Saturdays 06:54 UTC —
cron is UTC-only, so this is 07:54/08:54 `Europe/Zurich` depending on DST).

The root [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json)
just references this image (`"image": "ghcr.io/.../base:latest"`) instead of
building the Dockerfile locally, so its equivalent `postCreateCommand` steps
(apt packages, etc.) stay commented out — they're only a fallback for a plain
Microsoft base image.

### OpenTelemetry Collector (`otel-collector-contrib`, not auto-started)

The published
[`otel-collector-contrib`](https://github.com/bugrasan/devcontainers-features/tree/main/src/otel-collector-contrib)
Feature bakes the `otelcol-contrib` binary and a default OTLP → Azure
Application Insights config (`/etc/otelcol-contrib/config.yaml`) into the
image — with **`autoStart: false`**: `AUTO_START=false` is baked into the
Feature's `postStartCommand` hook at image-build time, so it exits immediately
on every container start. Nothing runs and nothing listens on 4317/4318 until
you start the collector yourself:

```bash
# only needed for the default config (resolved at collector startup, never baked in)
export APPLICATIONINSIGHTS_CONNECTION_STRING=...
otelcol-contrib --config /etc/otelcol-contrib/config.yaml
```

Use `--config <path>` with your own file to skip the App Insights default
entirely. (With `autoStart` disabled, the Feature's
`/usr/local/share/otel-collector-contrib/start.sh` helper is a no-op — run the
binary directly as above.)

### Why `pi`/`claude`/npm packages are Features, not Dockerfile `RUN` lines

`devcontainer build` only builds the Dockerfile, then layers Features
(including `node`) **on top of it** — there's no way for a plain Dockerfile
`RUN` to run *after* a Feature. So:

- **`uv`** doesn't need Node — it's `RUN` directly in the Dockerfile.
- **`eslint`/`typescript`/`pyright`/`typescript-language-server`** (the local
  [`npm-packages`](.devcontainer/base/features/npm-packages) Feature) and
  **`pi-dev`** need `npm`, which only exists once the `node` Feature layer
  applies — both declare `installsAfter: node` so the Feature installer runs
  in the right order.
- **`claude-code`** turns out not to need `npm` at all — confirmed by actually
  running `claude.ai/install.sh` non-interactively (no tty, no stdin): it's a
  self-contained native binary installer. The install fails some other way
  ("No terminal detected") for `pi.dev` specifically if Node/npm aren't
  present yet, which is exactly what `installsAfter: node` prevents.

Published from a separate repo:
[bugrasan/devcontainers-features](https://github.com/bugrasan/devcontainers-features)
(`claude-code`, `pi-dev`, `speckit`, `otel-collector-contrib`, `superfile`,
`herdr`). `speckit` installs the `specify` CLI (Spec-Driven Development) via
uv; it needs uv (from the Dockerfile) and Python (from the `python` Feature),
both already in this image. `herdr` installs the terminal multiplexer coding
agents run in; it installs the binary only and starts nothing, so run `herdr`
to open or reattach to a session.

## The `:base-sandbox` Image

[.devcontainer/base-sandbox/Dockerfile.trixie](.devcontainer/base-sandbox/Dockerfile.trixie)
builds the same stack as `:base` without a single Dev Container Feature, so it
builds with `docker build` alone:

```
ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox:latest
```

Everything each Feature used to do is a `RUN` line calling a script in
[.devcontainer/base-sandbox/scripts/](.devcontainer/base-sandbox/scripts/):
version resolution, architecture mapping and checksum verification included.

| | `:base` | `:base-sandbox` |
|---|---|---|
| built by | Dev Containers CLI, 12 Features | `docker buildx build`, one Dockerfile |
| base image | `mcr.microsoft.com/devcontainers/base:trixie` | `debian:trixie` |
| `sudo` | passwordless for `vscode` | **not installed** |
| SSH host keys | baked in by the `sshd` Feature | **generated on first start** |
| sshd runs as | root | `vscode`, unprivileged |
| Node.js | `node` Feature | upstream tarball, v24, checksum-verified |
| Python / pip / pipx | `python` Feature | from the OS (Debian 3.13) |
| `az` (Azure CLI) | not included | `uv tool install azure-cli` |
| `pi-dev` | included | not included |
| copilot auto-update check | disabled in `postCreateCommand` | never installed |
| Linux capabilities | container defaults | all dropped by the template |

Baked in: `node`/`npm` 24, OS `python3`/`pip`/`pipx`, `uv`, `gh`, `copilot`,
`claude`, `az`, `specify` (spec-kit), `otelcol-contrib`, `spf` (superfile),
`herdr`, the global npm packages (`editorconfig`, `eslint`, `typescript`,
`pyright`, `typescript-language-server`) and the agent LSP config.

### SSH host keys

The image ships none, on purpose: a host key baked into a published image is the
same key for everyone who pulls it. `/etc/ssh/ssh_host_*` is removed **in the
same layer** that installs `openssh-server`, so it is not recoverable from a
lower layer either.

`/usr/local/share/base-sandbox/sshd-init.sh` generates an ed25519 and an RSA key
on first start and then starts sshd **as the `vscode` user** on port 2222 — no
root and no capabilities are involved, because sshd only ever authenticates the
account it already runs as. It is idempotent, and it runs from two places: the
image `ENTRYPOINT` for plain `docker run`, and `postStartCommand` for dev
containers, whose CLI replaces the entrypoint.

### Publishing and retention

[.github/workflows/publish-base-sandbox-image.yml](.github/workflows/publish-base-sandbox-image.yml)
builds both architectures natively and publishes on pushes touching
`.devcontainer/base-sandbox/**`, and on a schedule (Saturdays 07:24 UTC — 30
minutes after the `:base` build, so the two do not compete for runners).
Scheduled runs build with `--no-cache`, since a cached `apt-get upgrade` would
replay the previous week's packages.

Every build publishes two tags: the floating `:latest` and an immutable
`:YYYYMMDD-<short-sha>`. After a successful smoke test,
[.github/scripts/prune-ghcr-versions.sh](.github/scripts/prune-ghcr-versions.sh)
keeps the current dated release plus the two before it and deletes the rest,
including the untagged per-architecture manifests the dropped ones leave behind.
`:latest`, `:latest-linux-*` and `:buildcache-*`, and the children of everything
kept, are never touched.

> A repository `GITHUB_TOKEN` can list versions of a **user-owned** package but
> is usually refused on DELETE. Add a `GHCR_PAT` repository secret (a personal
> access token with `delete:packages`) to enable retention. Without it the step
> logs the remedy as a warning and exits cleanly — it never fails a run whose
> image is already published.

## Dev Container Template: `base-sandbox-template`

[src/base-sandbox-template/](src/base-sandbox-template/) consumes the image
above and adds the parts that only exist at container run time: the cleared
environment, the socket sweep, and the dropped capabilities.

- **Template reference:** `ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox-template`
- **Options:** `sshdPort` (default `2222`) and `startSshd` (default `true`). Both
  are read at container start, so changing either needs a restart, not an image
  rebuild — unlike the `sshd` Feature, which reads them only at image-build time.

```bash
devcontainer templates apply -w /path/to/project \
  -t ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox-template:0
```

The name carries the `-template` suffix because templates and images share one
GHCR namespace: `base-sandbox` is already taken by the image.

## Hardening

Four layers, two of them on. The full rationale, what each costs and how to
enable the other two is in **[docs/hardening.md](docs/hardening.md)**.

| Layer | Status |
|---|---|
| 1 — no handles back to the host (cleared env, swept sockets, no copied credentials) | enabled |
| 2 — no privilege to take (no `sudo`, `--cap-drop=ALL`, `--security-opt=no-new-privileges`) | enabled |
| 3 — Docker socket proxy | documented, off (needs Compose) |
| 4 — outbound egress allowlist | documented, off (needs `NET_ADMIN`/`NET_RAW` back) |

Based on Daniel Demmel's
[Coding agents in secured VS Code dev containers](https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers).

Known costs: `ping` needs `NET_RAW` and stops working, the `code` CLI inside the
container stops working (its IPC socket is the one that executes commands on the
host), and `apt-get install` needs an image rebuild. Use `uv`, `pipx` or
`npm -g` — all three work without root.

## Tests

```bash
npm install -g bats @devcontainers/cli jsonc-parser
bats test/unit                      # host-side: retention logic, template configs
```

| Location | Runs | Covers |
|---|---|---|
| [test/unit/](test/unit/) | on the host, no Docker needed for most | GHCR retention selection, JSONC validity of every `devcontainer.json`, the template's hardening settings |
| [test/container/](test/container/) | inside the built image, in CI | every tool present, no `sudo`, no baked host keys, key generation, a real public-key login |

The container tests run in CI under the same `--cap-drop=ALL
--security-opt=no-new-privileges` the template applies, so they prove the image
works *when sandboxed*.

## LSP code intelligence

The image is wired so the three baked-in AI agent harnesses use **Language
Server Protocol** (go-to-definition, find-references, hover, diagnostics) —
semantic, AST-backed answers — instead of grepping/reading files as text. Each
concern lives in the agent's own Feature, **not** the OS-level Dockerfile.

| Agent harness | How LSP is wired | Servers used |
|-----|-----|-----|
| **Claude Code** | the `claude-code` Feature installs the `pyright-lsp` + `typescript-lsp` plugins at **user scope** (`claude plugin install`, after registering the marketplace) and sets `ENABLE_LSP_TOOL=1` via its `containerEnv` | `pyright-langserver`, `typescript-language-server` |
| **GitHub Copilot CLI** | user-scope `~/.copilot/lsp-config.json` written by the local `lsp-config` Feature | `pyright-langserver`, `typescript-language-server` |
| **VS Code Copilot** (agent mode) | built-in `usages` tool (`search/usages`, since v1.99; reference as `#usages`), with `chat.agent.enabled` in `customizations.vscode.settings` | Pylance (Python extension) + VS Code's built-in TypeScript features |

**Language-server binaries** come from the `npm-packages` Feature
(`pyright` → `pyright-langserver`, `typescript-language-server`) and the Python
Feature's Pylance extension. A plugin/config only *wires the connection* — the
binary must be on `PATH` for a server to activate.

`ENABLE_LSP_TOOL=1` is set by the `claude-code` Feature's `containerEnv` (and
mirrored in the root/template `containerEnv` for the swap-image case) — it is
**not** a Dockerfile `ENV`, since it belongs to Claude Code, not the base OS.
The local [`lsp-config`](.devcontainer/base/features/lsp-config) Feature writes
the Copilot CLI config and a short `~/.claude/CLAUDE.md` bias (nudge, not force).

> **Go:** `gopls-lsp` is **not** installed by default (no Go toolchain / `gopls`
> in this image). To enable it, add a Go Feature + `go install
> golang.org/x/tools/gopls@latest`, then add `gopls-lsp@claude-plugins-official`
> to the `claude-code` Feature's `lspPlugins` and `gopls` to the `lsp-config`
> Feature's Copilot config.

For repo-scoped bias, add `.github/copilot-instructions.md` (VS Code Copilot) or
`AGENTS.md` (Copilot CLI) to your project.

### Copilot CLI auto-update

The `copilot-cli` Feature runs an online update check on **every** container
start (its `postStartCommand`). The root and template `devcontainer.json`
disable it by removing the Feature's flag file
(`/etc/devcontainer-copilot-cli/auto-update`) in `postCreateCommand` — which
runs before that check, so it no-ops. `copilot` still refreshes to the latest
release at each weekly base-image rebuild; only the per-start network check is
suppressed. The Feature itself is left untouched (no version pinning). Remove
the `disable-copilot-autoupdate` `postCreateCommand` entry to restore it.

## Alternative: Plain Docker (Debian Trixie)

`.devcontainer/base/Dockerfile.trixie` is a fully self-contained alternative —
same apt packages, non-root `vscode` user, `chezmoi` dotfiles, `uv` baked in,
but no Dev Container Features.

```bash
docker build -f .devcontainer/base/Dockerfile.trixie -t trixie-dev \
   --build-arg USERNAME=vscode --build-arg USER_UID=1000 --build-arg USER_GID=1000 .
docker run --rm -it -v "$(pwd):/workspace" -w /workspace trixie-dev
```

## Quick Reference

| Task | Command |
|------|---------|
| Add remote (once) | `git remote add devcontainer-upstream https://<HOST>/<USER>/devcontainer-base-ai.git` |
| Fetch updates | `git fetch devcontainer-upstream` |
| View upstream commits | `git log devcontainer-upstream/main --oneline -- .devcontainer/devcontainer.json` |
| View diff | `git diff HEAD...devcontainer-upstream/main -- .devcontainer/devcontainer.json` |
| Grab latest file | `git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json` |
| Cherry-pick a commit | `git cherry-pick <hash>` |
| Interactive partial apply | `git checkout -p devcontainer-upstream/main -- .devcontainer/devcontainer.json` |
| Apply the `base-ai` Template | `devcontainer templates apply -w <dir> -t ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0` |
| Apply the `base-sandbox` Template | `devcontainer templates apply -w <dir> -t ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox-template:0` |
| Pull the `:base` image | `docker pull ghcr.io/bugrasan/devcontainer-base-ai/base:latest` |
| Pull the `:base-sandbox` image | `docker pull ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox:latest` |
| Build `:base-sandbox` locally | `docker build -f .devcontainer/base-sandbox/Dockerfile.trixie -t base-sandbox .devcontainer/base-sandbox` |
| SSH into a `base-sandbox` container | `ssh -p 2222 vscode@localhost` |
| Run the host-side tests | `bats test/unit` |

## Repository Layout

```
.
├── .devcontainer/
│   ├── devcontainer.json          # dev container for THIS repo (uses the :base image)
│   ├── base/
│   │   ├── devcontainer.json      # build-only definition published by publish-base-image.yml
│   │   ├── Dockerfile.mcr-trixie  # source Dockerfile actually baked into the :base image
│   │   ├── Dockerfile.trixie      # unused by :base - see "Alternative: Plain Docker" below
│   │   └── features/              # local Features: npm-packages, lsp-config
│   └── base-sandbox/
│       ├── Dockerfile.trixie      # the :base-sandbox image - no Features at all
│       └── scripts/               # build-time installers + the runtime sshd/hardening scripts
├── src/
│   ├── base-ai/                   # published by publish-templates.yml
│   └── base-sandbox-template/     # ditto - consumes the :base-sandbox image
├── docs/hardening.md              # the four hardening layers, what is on and why
├── test/
│   ├── unit/                      # host-side: retention logic, template configs
│   └── container/                 # run inside the built image by CI
├── .github/
│   ├── scripts/                   # GHCR retention
│   └── workflows/
│       ├── publish-templates.yml
│       ├── publish-base-image.yml
│       └── publish-base-sandbox-image.yml
└── LICENSE
```

## License

MIT — see [LICENSE](LICENSE).
