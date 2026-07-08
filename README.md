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
  devcontainer templates apply -w /path/to/project -t ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0.1.0
  ```

> **One-time setup:** GHCR packages default to private. Make `base-ai` and
> `base` public once via `github.com/users/bugrasan/packages` → package →
> **Settings → Danger Zone → Change visibility**. This can't be automated with
> the default `GITHUB_TOKEN`.

## The `:base` Image

[.devcontainer/base/devcontainer.json](.devcontainer/base/devcontainer.json) is
a build-only definition (not meant to be opened in VS Code) that builds
[Dockerfile.mcr-trixie](.devcontainer/base/Dockerfile.mcr-trixie) plus the same
Features as the root devcontainer.json (`common-utils`, `sshd`, `node`,
`python`, `github-cli`, `copilot-cli`), baking them all into:

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

### Why `pi`/`claude` install via `postCreateCommand`, not the Dockerfile

`devcontainer build` only builds the Dockerfile, then layers Features
(including `node`) **on top of it** — it never runs `postCreateCommand`. So:

- **`uv`** doesn't need Node — it's `RUN` directly in the Dockerfile.
- **`pi.dev`/`claude.ai` installers need `npm`**, which only exists once the
  `node` Feature layer is applied *after* the Dockerfile builds. Baking them
  into the Dockerfile fails non-interactively ("No terminal detected"). They're
  installed instead via `postCreateCommand` in devcontainer.json (root and
  template), which always runs after Features are in place.

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
├── src/base-ai/                # published by publish-templates.yml
├── .github/workflows/
│   ├── publish-templates.yml
│   └── publish-base-image.yml
└── LICENSE
```

## License

MIT — see [LICENSE](LICENSE).
