# devcontainer-base-ai

Debian trixie dev container for AI development.
It ships Node, Python, AI coding agents, language servers, and common CLI tools.

## Artifacts

| Artifact | Reference and tags | Contents | Built by |
|---|---|---|---|
| `:base` image | `ghcr.io/bugrasan/devcontainer-base-ai/base`<br>`latest` (amd64 and arm64), `latest-linux-amd64`, `latest-linux-arm64`<br>`buildcache-*` tags are build cache only | [Dockerfile.mcr-trixie](.devcontainer/base/Dockerfile.mcr-trixie): CLI tools such as `ripgrep`, `fzf`, `jq`, `lazygit`, `bats`, plus `uv`<br>Features: `common-utils`, `node` 24, `python`, `github-cli`, `copilot-cli`, `claude-code`, `speckit`, `otel-collector-contrib` (not auto-started), `superfile`, `herdr`<br>Local Features: [`npm-packages`](.devcontainer/base/features/npm-packages) (`eslint`, `typescript`, `pyright`, `typescript-language-server`, `editorconfig`, and the bash, yaml, json, html, css, and dockerfile language servers), [`lsp-servers`](.devcontainer/base/features/lsp-servers) (`marksman` for Markdown, `taplo` for TOML; jdtls, terraform-ls, and LemMinx available, commented out), [`lsp-config`](.devcontainer/base/features/lsp-config) (local plugin marketplace `base-ai-lsp` that wires the language servers into Copilot CLI and Claude Code, Claude Code nudge to prefer language servers)<br>Language servers per agent: [src/base-ai/NOTES.md](src/base-ai/NOTES.md#lsp-code-intelligence) | [publish-base-image.yml](.github/workflows/publish-base-image.yml): weekly (Saturday 06:54 UTC), on push to `main` that changes `.devcontainer/base/**` or the workflow, and manually; checked by [smoke-test.sh](.devcontainer/base/smoke-test.sh) |
| `base-ai` Template | `ghcr.io/bugrasan/devcontainer-base-ai/base-ai`<br>`latest`, `<major>`, `<major>.<minor>`, `<version>` | [src/base-ai/](src/base-ai/): `devcontainer.json` that uses the `:base` image, two fallback Dockerfiles, `.gitignore`<br>Option `sshdPort` (default `2222`): the port sshd listens on and VS Code forwards<br>Bump `version` in [devcontainer-template.json](src/base-ai/devcontainer-template.json) to publish a release | [publish-templates.yml](.github/workflows/publish-templates.yml): on push to `main` that changes `src/**` or the workflow, and manually; also regenerates `src/base-ai/README.md` |
| Collection metadata | `ghcr.io/bugrasan/devcontainer-base-ai` | Index of the Templates in [src/](src/) | [publish-templates.yml](.github/workflows/publish-templates.yml) |
| Root `devcontainer.json` | Not published | [.devcontainer/devcontainer.json](.devcontainer/devcontainer.json): dev container for this repo, uses the `:base` image, applies the maintainer's chezmoi dotfiles | – |
| `Dockerfile.trixie` | Not published | [.devcontainer/base/Dockerfile.trixie](.devcontainer/base/Dockerfile.trixie): plain Docker image with the same CLI tools and `uv`, but no Node, agents, or language servers | – |

## Usage

The Template needs `~/.ssh/id_ed25519.pub` on the host.
The Template and the root config set `TZ=Europe/Zurich` and auto-approve VS Code agent tool calls and terminal commands.

Apply the Template to a project:

```bash
devcontainer templates apply -w /path/to/project -t ghcr.io/bugrasan/devcontainer-base-ai/base-ai:0
```

The Template is not on the public [containers.dev](https://containers.dev/templates) index, so editor template pickers don't list it.

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
To allow anonymous pulls, make the `base` and `base-ai` packages public: package settings → **Danger Zone** → [**Change visibility**](https://docs.github.com/en/packages/learn-github-packages/configuring-a-packages-access-control-and-visibility).
The collection package is optional.
You can't make a public package private again.

## More details

- [src/base-ai/NOTES.md](src/base-ai/NOTES.md): SSH key, language server setup, OpenTelemetry Collector, and Copilot CLI auto-update
- [.devcontainer/base/devcontainer.json](.devcontainer/base/devcontainer.json): Feature options and the reasons behind them

## License

MIT, see [LICENSE](LICENSE).
