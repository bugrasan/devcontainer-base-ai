# devcontainer-base-ai

Base devcontainer configuration for AI/ML development projects.

This repo provides three related things:

1. **[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json)** — the one-size-fits-all dev container used to develop *this* repo (and copyable into other projects, see [Usage](#usage) below).
2. **[src/base-ai/](src/base-ai/)** — the same configuration packaged as a [Dev Container Template](https://containers.dev/implementors/templates/), published to GHCR (not listed on the public [containers.dev](https://containers.dev/templates) index). See [Dev Container Template](#dev-container-template-base-ai).
3. **[.devcontainer/base/](.devcontainer/base/)** — the definition used to bake `Dockerfile.mcr-trixie` + the Features below into a pre-built image, rebuilt every Saturday and consumed by (1) via its `image` property. See [The `:base` Image](#the-base-image).

## Usage

### Initial Setup in a New Project

1. **Add this repo as a remote** in your project:

   ```bash
   git remote add devcontainer-upstream https://<HOST>/<USER>/devcontainer-base-ai.git
   git fetch devcontainer-upstream
   ```

2. **Copy the devcontainer configuration** to your project:

   ```bash
   git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json
   git commit -m "Add devcontainer.json from devcontainer-base-ai"
   ```

### Syncing Updates

When improvements are made to this base configuration, you can selectively sync them to your project.

#### Fetch Latest Changes

```bash
git fetch devcontainer-upstream
```

#### View Upstream Commits

See what changed in the upstream devcontainer.json:

```bash
git log devcontainer-upstream/main --oneline -- .devcontainer/devcontainer.json
```

#### View Diff Against Your Current Version

```bash
git diff HEAD...devcontainer-upstream/main -- .devcontainer/devcontainer.json
```

### Sync Strategies

Choose the approach that fits your needs:

#### Option 1: Replace with Latest Version

Overwrite your local file with the latest upstream version:

```bash
git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json
git diff --cached  # Review the changes
git commit -m "Sync devcontainer.json from devcontainer-base-ai"
```

#### Option 2: Cherry-pick Specific Commits

Apply only specific improvements:

```bash
# Find the commit you want
git log devcontainer-upstream/main --oneline -- .devcontainer/devcontainer.json

# Cherry-pick it
git cherry-pick <commit-hash>
```

If the commit touches files you don't want, use the no-commit flag:

```bash
git cherry-pick -n <commit-hash>
git reset HEAD -- <files-to-exclude>
git checkout -- <files-to-exclude>
git commit -m "Cherry-pick devcontainer improvement: <description>"
```

#### Option 3: Interactive Partial Apply

Selectively apply individual changes (hunks):

```bash
git checkout -p devcontainer-upstream/main -- .devcontainer/devcontainer.json
```

This prompts you to accept or reject each change individually.

## Dev Container Template: `base-ai`

[src/base-ai/](src/base-ai/) packages the same configuration as a
[Dev Container Template](https://containers.dev/implementors/templates/),
following the layout from
[devcontainers/template-starter](https://github.com/devcontainers/template-starter):

```
src/
└── base-ai/
    ├── devcontainer-template.json
    └── .devcontainer/
        ├── devcontainer.json
        └── Dockerfile.trixie
```

It's published as an OCI artifact to GHCR by
[.github/workflows/publish-templates.yml](.github/workflows/publish-templates.yml)
whenever a change under `src/**` is pushed to `main`, using the
[`devcontainers/action`](https://github.com/devcontainers/action) GitHub Action —
the same mechanism documented in the
[Templates distribution spec](https://containers.dev/implementors/templates-distribution/).

- **Template reference:** `ghcr.io/bugrasan/devcontainer-base-ai/base-ai`
- **Collection metadata package:** `ghcr.io/bugrasan/devcontainer-base-ai`

### Not listed on the public index

This Template is **intentionally not submitted** to the public
[containers.dev/templates](https://containers.dev/templates) index (that would
require a PR to
[devcontainers/devcontainers.github.io](https://github.com/devcontainers/devcontainers.github.io)).
That means it won't show up in the VS Code "Add Dev Container Configuration
Files" picker or the GitHub Codespaces template gallery — it must be referenced
directly by its OCI reference.

### Consuming the Template directly

With the [Dev Container CLI](https://github.com/devcontainers/cli) installed:

```bash
devcontainer templates apply \
  -w /path/to/your/project \
  -t ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0.1.0
```

Or fetch/inspect the raw OCI artifact with [oras](https://oras.land/):

```bash
oras pull ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0.1.0
```

### One-time: make the GHCR packages public

GHCR packages default to **private**, even when the source repo is public.
"Not on the public index" only refers to the containers.dev listing above — to
let others pull the Template (and the [`:base` image](#the-base-image)) at
all, visibility must be flipped once, manually, per package:

1. Go to `https://github.com/users/bugrasan/packages`
2. Open the `devcontainer-base-ai/base-ai` package (and `devcontainer-base-ai/base`)
3. **Package settings** → **Danger Zone** → **Change visibility** → **Public**

This can't be reliably automated from the workflow with the default
`GITHUB_TOKEN`, so it's a manual step after the first successful publish.

## The `:base` Image

[.devcontainer/base/devcontainer.json](.devcontainer/base/devcontainer.json)
defines a minimal devcontainer used only for building — it's not meant to be
opened in VS Code directly. It reuses
[.devcontainer/base/Dockerfile.mcr-trixie](.devcontainer/base/Dockerfile.mcr-trixie) as its
`build.dockerfile` and declares the same
[Features](https://containers.dev/features) as the root devcontainer.json
(`common-utils`, `sshd`, `node`, `python`, `github-cli`, `copilot-cli`), so the
published image already contains all of them baked in — no need to install
Features at container-creation time.

[.github/workflows/publish-base-image.yml](.github/workflows/publish-base-image.yml)
builds this definition with the
[`devcontainers/ci`](https://github.com/devcontainers/ci) GitHub Action and
pushes a multi-arch (`linux/amd64` + `linux/arm64`) image to:

```
ghcr.io/bugrasan/devcontainer-base-ai/base:latest
```

### Rebuild schedule

The workflow runs on a schedule and on pushes to `main` that touch the base definition:

```yaml
on:
  push:
    branches:
      - main
    paths:
      - ".devcontainer/base/**"
      - ".github/workflows/publish-base-image.yml"
  schedule:
    - cron: "54 6 * * 6"   # every Saturday, 06:54 UTC
  workflow_dispatch: {}
```

GitHub Actions cron schedules are UTC-only and do not adjust for daylight
saving time, so the cron expression always fires at 06:54 UTC regardless of
the season (07:54 or 08:54 local `Europe/Zurich` wall-clock time, depending on
whether CET or CEST is in effect).

### How the root devcontainer consumes it

[.devcontainer/devcontainer.json](.devcontainer/devcontainer.json) references
the published image directly instead of building `Dockerfile.trixie` locally:

```jsonc
"image": "ghcr.io/bugrasan/devcontainer-base-ai/base:latest",

// either image or self-build docker image
// "build": {
// 	"dockerfile": "base/Dockerfile.trixie"
// },
```

Because the apt packages from `Dockerfile.trixie` (`bat`, `eza`, `fzf`,
`ripgrep`, `jq`, `lazygit`, etc.) are already baked into the `:base` image, the
equivalent `postCreateCommand` step (`debian-dpkg`) stays commented out in
`devcontainer.json` — it's only needed as a fallback when using a plain
Microsoft base image instead.

## Alternative: Plain Docker (Debian Trixie)

An alternative image definition is available at `.devcontainer/base/Dockerfile.trixie`.
It installs the same Debian packages used by the `:base` image above, creates a
non-root `vscode` user, and applies dotfiles via `chezmoi`.

> **Note:** This plain Dockerfile bakes in the same `uv`, `pi.dev`, and
> `claude` installs as `.devcontainer/base/Dockerfile.mcr-trixie`, but does
> not use Dev Container Features — it's a fully self-contained Dockerfile
> build.

### Build

```bash
docker build -f .devcontainer/base/Dockerfile.trixie -t trixie-dev .
```

Optional: customize user name/uid/gid at build time:

```bash
docker build \
   -f .devcontainer/base/Dockerfile.trixie \
   -t trixie-dev \
   --build-arg USERNAME=vscode \
   --build-arg USER_UID=1000 \
   --build-arg USER_GID=1000 \
   .
```

### Run

```bash
docker run --rm -it trixie-dev
```

Optional: mount the current project into the container:

```bash
docker run --rm -it \
   -v "$(pwd):/workspace" \
   -w /workspace \
   trixie-dev
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
| Apply the `base-ai` Template | `devcontainer templates apply -w <dir> -t ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0.1.0` |
| Pull the `:base` image | `docker pull ghcr.io/bugrasan/devcontainer-base-ai/base:latest` |

## Repository Layout

```
.
├── .devcontainer/
│   ├── devcontainer.json      # dev container for THIS repo (uses the :base image)
│   └── base/
│       ├── devcontainer.json  # build-only definition published by publish-base-image.yml
│       └── Dockerfile.trixie  # source Dockerfile baked into the :base image
├── src/
│   └── base-ai/
│       ├── devcontainer-template.json
│       └── .devcontainer/     # published by publish-templates.yml
├── .github/
│   └── workflows/
│       ├── publish-templates.yml     # on push to main touching src/**
│       └── publish-base-image.yml    # on schedule, Saturday 06:54 UTC
└── LICENSE
```

## License

MIT — see [LICENSE](LICENSE).
