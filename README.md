# devcontainer-base-ai

Debian trixie dev container for AI/ML development.
It ships Node, Python, AI coding agents, language servers, and common CLI tools.

## Artifacts

| Artifact | Reference and tags | Contents | Built by |
|---|---|---|---|
| `:base` image | `ghcr.io/bugrasan/devcontainer-base-ai/base`<br>`latest` (amd64 + arm64), `latest-linux-amd64`, `latest-linux-arm64` | [Dockerfile.mcr-trixie](.devcontainer/base/Dockerfile.mcr-trixie): CLI tools (e.g. `ripgrep`, `fzf`, `jq`, `lazygit`, `bats`) and `uv`<br>Features: `common-utils`, `sshd`, `node` 24, `python`, `github-cli`, `copilot-cli`, `claude-code`, `speckit`, `otel-collector-contrib` (not auto-started), `superfile`, and `herdr`<br>Local Features: [`npm-packages`](.devcontainer/base/features/npm-packages) (`eslint`, `typescript`, `pyright`, `typescript-language-server`, `editorconfig`) and [`lsp-config`](.devcontainer/base/features/lsp-config) (LSP setup for Claude Code and Copilot CLI) | [publish-base-image.yml](.github/workflows/publish-base-image.yml): weekly (Saturday 06:54 UTC) and on push to `.devcontainer/base/**` |
| `base-ai` Template | `ghcr.io/bugrasan/devcontainer-base-ai/base-ai`<br>`latest`, `<major>`, `<major>.<minor>`, `<version>` | [src/base-ai/](src/base-ai/): a `devcontainer.json` that uses the `:base` image<br>Option: `sshdPort` (default `2222`) | [publish-templates.yml](.github/workflows/publish-templates.yml): on push to `src/**` |
| Collection metadata | `ghcr.io/bugrasan/devcontainer-base-ai` | Index of the Templates in [src/](src/) | [publish-templates.yml](.github/workflows/publish-templates.yml) |
| Root `devcontainer.json` | Not published; copy it from this repo | [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json): dev container for this repo, uses the `:base` image | – |
| `Dockerfile.trixie` | Not published | [.devcontainer/base/Dockerfile.trixie](.devcontainer/base/Dockerfile.trixie): plain Docker alternative with the same CLI tools, no Features | – |

The `base-ai` version lives in [devcontainer-template.json](src/base-ai/devcontainer-template.json).

## Usage

Apply the Template to a project:

```bash
devcontainer templates apply -w /path/to/project -t ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0
```

Or reference the image in your own `devcontainer.json`:

```json
"image": "ghcr.io/bugrasan/devcontainer-base-ai/base:latest"
```

Or copy this repo's config into a project, and repeat to sync later changes:

```bash
git remote add devcontainer-upstream https://<HOST>/<USER>/devcontainer-base-ai.git
git fetch devcontainer-upstream
git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json
```

The Template is not on the public [containers.dev](https://containers.dev/templates) index, so editor template pickers don't list it.

## One-time setup

New GHCR packages in a personal account start private.
Make the `base` and `base-ai` packages public for anonymous pulls: package settings → **Danger Zone** → **Change visibility**.
A public package can't be made private again.
See [GitHub Docs](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).

## More details

- [src/base-ai/NOTES.md](src/base-ai/NOTES.md): SSH key, LSP setup, OpenTelemetry Collector, and Copilot CLI auto-update
- [.devcontainer/base/devcontainer.json](.devcontainer/base/devcontainer.json): Feature options and the reasons behind them

## License

MIT, see [LICENSE](LICENSE).
