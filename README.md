# devcontainer-base-ai

Debian trixie dev container for AI development.
It ships Node, Python, AI coding agents, language servers, and common CLI tools.

## Artifacts

| Artifact | Reference and tags | Contents | Built by |
|---|---|---|---|
| `:base` image | `ghcr.io/bugrasan/devcontainer-base-ai/base`<br>`latest` (amd64 and arm64), `latest-linux-amd64`, `latest-linux-arm64`<br>`buildcache-*` tags are build cache only | [Dockerfile.mcr-trixie](.devcontainer/base/Dockerfile.mcr-trixie): CLI tools such as `ripgrep`, `fzf`, `jq`, `lazygit`, `bats`, plus `uv`<br>Features: `common-utils`, `node` 24, `python`, `github-cli`, `copilot-cli`, `claude-code`, `speckit`, `otel-collector-contrib` (not auto-started), `superfile`, `herdr`<br>Local Features: [`npm-packages`](.devcontainer/base/features/npm-packages) (`eslint`, `typescript`, `pyright`, `typescript-language-server`, `editorconfig`), [`lsp-config`](.devcontainer/base/features/lsp-config) (Copilot CLI language server config, Claude Code nudge to prefer language servers) | [publish-base-image.yml](.github/workflows/publish-base-image.yml): weekly (Saturday 06:54 UTC), on push to `main` that changes `.devcontainer/base/**` or the workflow, and manually |
| `base-ai` Template | `ghcr.io/bugrasan/devcontainer-base-ai/templates/base-ai`<br>Until the move to `templates/`: `ghcr.io/bugrasan/devcontainer-base-ai/base-ai`, no longer updated<br>`latest`, `<major>`, `<major>.<minor>`, `<version>` | [src/base-ai/](src/base-ai/): `devcontainer.json` that uses the `:base` image, two fallback Dockerfiles, `.gitignore`<br>Option `sshdPort` (default `2222`): the port sshd listens on and VS Code forwards<br>Bump `version` in [devcontainer-template.json](src/base-ai/devcontainer-template.json) to publish a release | [publish-templates.yml](.github/workflows/publish-templates.yml): on push to `main` that changes `src/**` or the workflow, and manually; also regenerates `src/base-ai/README.md` |
| `sbx` Template | `ghcr.io/bugrasan/devcontainer-base-ai/templates/sbx`<br>`latest`, `<major>`, `<major>.<minor>`, `<version>` | [src/sbx/](src/sbx/): sandbox – agent container without network plus a Squid egress proxy; compose files, `devcontainer.json`, allowlist, Dockerfiles, acceptance tests<br>Bump `version` in [devcontainer-template.json](src/sbx/devcontainer-template.json) to publish a release; the images use the same version | [publish-templates.yml](.github/workflows/publish-templates.yml), as for `base-ai` |
| `sbx-agent` and `sbx-proxy` images | `ghcr.io/bugrasan/devcontainer-base-ai/sbx-agent`<br>`ghcr.io/bugrasan/devcontainer-base-ai/sbx-proxy`<br>`latest` and `<version>` (amd64 and arm64), per-arch `*-linux-amd64` and `*-linux-arm64`<br>`buildcache-*` tags are build cache only | [Dockerfile.agent](src/sbx/.devcontainer/Dockerfile.agent): the `:base` image plus `socat` and test tools, no `sudo`<br>[Dockerfile.proxy](src/sbx/.devcontainer/Dockerfile.proxy): Squid and `socat`, runs as UID 13 | [publish-sbx-images.yml](.github/workflows/publish-sbx-images.yml): runs the acceptance tests on Docker before it pushes; weekly (Saturday 08:54 UTC), on push to `main` that changes the Dockerfiles or the workflow, and manually |
| Collection metadata | `ghcr.io/bugrasan/devcontainer-base-ai/templates` | Index of the Templates in [src/](src/) | [publish-templates.yml](.github/workflows/publish-templates.yml) |
| Root `devcontainer.json` | Not published | [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json): dev container for this repo, uses the `:base` image, applies the maintainer's chezmoi dotfiles | – |
| `Dockerfile.trixie` | Not published | [.devcontainer/base/Dockerfile.trixie](.devcontainer/base/Dockerfile.trixie): plain Docker image with the same CLI tools and `uv`, but no Node, agents, or language servers | – |

## Usage

The Template needs `~/.ssh/id_ed25519.pub` on the host.
The Template and the root config set `TZ=Europe/Zurich` and auto-approve VS Code agent tool calls and terminal commands.

Apply the Template to a project:

```bash
devcontainer templates apply -w /path/to/project -t ghcr.io/bugrasan/devcontainer-base-ai/templates/base-ai:0
```

For the sandbox, use `templates/sbx:0` instead; see [src/sbx/NOTES.md](src/sbx/NOTES.md).

The Templates are not on the public [containers.dev](https://containers.dev/templates) index, so editor template pickers don't list them.

Or reference the image in your own `devcontainer.json`:

```json
"image": "ghcr.io/bugrasan/devcontainer-base-ai/base:latest"
```

Or copy this repo's config into a project.
It applies the maintainer's chezmoi dotfiles; remove the `chezmoi` entry from `postCreateCommand` to skip them.
To sync later changes, rerun the last two commands.
They overwrite local edits, including a removed `chezmoi` entry.

```bash
git remote add devcontainer-upstream https://<HOST>/<USER>/devcontainer-base-ai.git
git fetch devcontainer-upstream
git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json
```

## One-time setup (publisher)

New GitHub Container Registry packages in a personal account start private.
To allow anonymous pulls, make the `base`, `sbx-agent`, `sbx-proxy`, `templates/base-ai`, and `templates/sbx` packages public: package settings → **Danger Zone** → [**Change visibility**](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).
The collection package is optional.
You can't make a public package private again.

## More details

- [src/sbx/.devcontainer/README.md](src/sbx/.devcontainer/README.md): sandbox design, limits, and todos; [docs/arch-decisions.md](docs/arch-decisions.md): reasons
- [src/base-ai/NOTES.md](src/base-ai/NOTES.md): SSH key, language server setup, OpenTelemetry Collector, and Copilot CLI auto-update
- [.devcontainer/base/devcontainer.json](.devcontainer/base/devcontainer.json): Feature options and the reasons behind them

## License

MIT, see [LICENSE](LICENSE).
