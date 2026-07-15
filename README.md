# devcontainer-base-ai

Base devcontainer configuration for AI/ML development projects. Three related pieces:

1. **[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json)** — one-size-fits-all dev container for *this* repo, copyable into other projects.
2. **[src/base-ai/](src/base-ai/)** — same config packaged as a [Dev Container Template](https://containers.dev/implementors/templates/), published to GHCR (not on the public index).
3. **[.devcontainer/base/](.devcontainer/base/)** — bakes `Dockerfile.mcr-trixie` + Features into a pre-built image, rebuilt weekly, consumed by (1) via its `image` property.

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
> **Settings → Danger Zone → Change visibility**: the `base` image and the
> `base-ai` template (required for anonymous pull/apply), plus the
> `devcontainer-base-ai` collection metadata package (optional). This can't be
> automated with the default `GITHUB_TOKEN`.

## The `:base` Image

[.devcontainer/base/devcontainer.json](.devcontainer/base/devcontainer.json) is
a build-only definition (not meant to be opened in VS Code) that builds
[Dockerfile.mcr-trixie](.devcontainer/base/Dockerfile.mcr-trixie) plus the same
Features as the root devcontainer.json (`common-utils`, `sshd`, `node`,
`python`, `github-cli`, `copilot-cli`, plus the local `npm-packages` Feature
and the published `claude-code`/`pi-dev`/`speckit` Features), baking them all into:

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
(`claude-code`, `pi-dev`, `speckit`). `speckit` installs the `specify` CLI
(Spec-Driven Development) via uv; it needs uv (from the Dockerfile) and Python
(from the `python` Feature), both already in this image.

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
| Pull the `:base` image | `docker pull ghcr.io/bugrasan/devcontainer-base-ai/base:latest` |

## Repository Layout

```
.
├── .devcontainer/
│   ├── devcontainer.json          # dev container for THIS repo (uses the :base image)
│   └── base/
│       ├── devcontainer.json      # build-only definition published by publish-base-image.yml
│       ├── Dockerfile.mcr-trixie  # source Dockerfile actually baked into the :base image
│       ├── Dockerfile.trixie      # unused by :base - see "Alternative: Plain Docker" below
│       └── features/npm-packages/ # local Feature: editorconfig, eslint, typescript, pyright, typescript-language-server
├── src/base-ai/                # published by publish-templates.yml
├── .github/workflows/
│   ├── publish-templates.yml
│   └── publish-base-image.yml
└── LICENSE
```

## License

MIT — see [LICENSE](LICENSE).
