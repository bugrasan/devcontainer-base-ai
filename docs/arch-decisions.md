# Architecture decisions

Short records of decisions behind the `:base` image.
Each entry states the decision, the reason, and its consequences.

## D1 – Self-owned local plugin marketplace for language servers

- Decision: the `lsp-config` Feature generates a local marketplace `base-ai-lsp` at `/usr/local/share/base-ai-lsp`, with one plugin per language server; no third-party marketplace is used
- Why:
  - third-party LSP plugins carried risks: `SessionStart` hooks that run `brew` or `npm install -g`, repos without a license, and a Dockerfile plugin keyed on `"Dockerfile"`, which Claude Code ignores because extension keys must start with a dot
  - one server table in `install.sh` generates both manifests per plugin, so Claude Code and Copilot CLI get the same servers from one source
- Consequences:
  - each plugin has `.claude-plugin/plugin.json` (Claude Code, `extensionToLanguage`) and `.github/plugin/plugin.json` (Copilot CLI, `fileExtensions`); neither agent accepts the other's key
  - Copilot CLI loads the plugins live from the folder, so the folder must stay in the image
  - servers are no longer written to `~/.copilot/lsp-config.json`, so each server has one source

## D2 – marksman serves Markdown

- Decision: `.md` and `.markdown` go to `marksman`; `vscode-markdown-language-server` (from `vscode-langservers-extracted`) stays installed but unwired
- Why: the vscode Markdown server needs the client to implement the custom `markdown/parse` request, and its README says it has not been tested with clients other than VS Code ([vscode-markdown-languageserver](https://registry.npmjs.org/vscode-markdown-languageserver)); Claude Code and Copilot CLI are generic LSP clients
- Consequences: `marksman` is a separate download in the `lsp-servers` Feature (see `tech-debt.md`, unpinned downloads)

## D7 – pyright: official plugin for Claude Code, local copy for Copilot CLI

- Decision: Claude Code keeps `pyright-lsp` from `claude-plugins-official` (the `claude-code` Feature's `lspPlugins`); Copilot CLI gets `pyright-lsp` from `base-ai-lsp`
- Why: Copilot CLI 1.0.116 rejects the `anthropics/claude-plugins-official` marketplace file (`Invalid marketplace.json: plugins.302.source: Invalid input`)
- Consequences: the `pyright` row in the server table is marked `copilot` only; the smoke test checks the official plugin for Claude Code and the local one for Copilot CLI
- TypeScript was part of this decision until D11

## D8 – Keep the online YAML schema download

- Decision: `yaml-language-server` keeps its default, which downloads the SchemaStore catalog and matching schemas
- Why: schemas add validation, completion, and hover for known files, such as GitHub workflows; the alternatives either block the download or need yaml settings that Copilot CLI cannot send
- Consequences:
  - the server starts the download only when the client sends `workspace/didChangeConfiguration`; Copilot CLI 1.0.116 doesn't, so it gets no schemas (tested); Claude Code likely does (unverified)
  - the comment at the yaml row in `.devcontainer/base/features/lsp-config/install.sh` lists the tested alternatives for offline or sandboxed containers

## D9 – `docker.docker` for Dockerfile support in VS Code

- Decision: the template adds `docker.docker` (Docker DX), not `ms-azuretools.vscode-containers`
- Why: Docker DX focuses on editing; the Containers extension also manages containers, which needs a Docker daemon the dev container doesn't have
- Consequences: VS Code gets Dockerfile editing support only

## D10 – eslint language server not wired

- Decision: the `eslint` row in the `lsp-config` server table stays commented out; `vscode-langservers-extracted` stays installed, because it brings the json, html, and css servers
- Why (tested with Copilot CLI 1.0.116, 2026-11-27):
  - Copilot CLI starts one server per file extension, and eslint shares `.js` and `.ts` with `typescript`, so it never started
  - it has no document symbols or hover, which the agents use most
  - `vscode-eslint-language-server` fails when the client answers `workspace/configuration` without the VS Code extension's settings, and reports diagnostics only through pull requests (`textDocument/diagnostic`), which Copilot CLI doesn't send
- Consequences: no eslint diagnostics in the agents; run `eslint` from the shell instead; VS Code keeps the `dbaeumer.vscode-eslint` extension

## D11 – TypeScript 7's own language server for both agents

- Decision: the `typescript` plugin in `base-ai-lsp` runs `tsc --lsp --stdio` for both agents; the `claude-code` Feature's `lspPlugins` is set to `pyright-lsp@claude-plugins-official` only
- Why: the npm `typescript` package is TypeScript 7 (typescript-go), which ships no `lib/tsserver.js`; `typescript-language-server`, also used by `typescript-lsp@claude-plugins-official`, then fails at `initialize` with "Could not find a valid TypeScript installation" ([typescript-language-server#1110](https://github.com/typescript-language-server/typescript-language-server/issues/1110)); `tsc --lsp --stdio` is TypeScript 7's own server, not a workaround, and returned symbols and hover with Copilot CLI 1.0.116 (tested 2026-11-27)
- Consequences:
  - `typescript-language-server` is no longer installed by `npm-packages`; a project with a local TypeScript 6 or older that needs it can install it locally
  - the smoke test fails if `typescript-lsp@claude-plugins-official` is enabled
  - `lsp-check.py` starts every server both agents configure, so a broken command fails the smoke test

## Deferred language servers

- Decision: jdtls (Java), terraform-ls, and LemMinx (XML) stay as commented-out code in the `lsp-servers` Feature and as commented-out rows in the `lsp-config` server table
- Why: keep the image small until a project needs them; jdtls also needs `openjdk-25-jdk-headless`, because it requires Java 25 or later
- Consequences:
  - to enable one, see "How do I enable a deferred language server?" in `dev-faq.md`
  - for Claude Code, Java uses `jdtls-lsp@claude-plugins-official`, commented out next to the `claude-code` Feature in `.devcontainer/base/devcontainer.json`
