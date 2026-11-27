# Tech debt

Known shortcuts and open risks.
No workarounds are in place yet; log each future workaround here, with a link to its upstream issue and its entry in `arch-decisions.md`.

## Unpinned downloads (`TODO(pin)`)

- What: every language server tracks the latest release, with no version or checksum pin:
  - `marksman` and `taplo` in `.devcontainer/base/features/lsp-servers/install.sh`
  - the npm packages in `.devcontainer/base/features/npm-packages` (`bash-language-server`, `yaml-language-server`, `vscode-langservers-extracted`, `dockerfile-language-server-nodejs`, and the existing ones)
- Risk: a new release can break the weekly rebuild, or change behavior without a code change
- Fix: pin versions and checksums; search for `TODO(pin)`

## Stale `vscode-langservers-extracted`

- What: version 4.10.0 was published on 2024-05-08 ([registry](https://registry.npmjs.org/vscode-langservers-extracted)), so its html, css, json, and eslint servers are about 2.5 years old
- Risk: missing fixes and newer language features
- Fix: revisit together with the `TODO(pin)` work; look for a maintained source of these servers

## eslint diagnostics with agent clients (resolved: dropped)

- What: `vscode-eslint-language-server` needs VS Code-specific settings through `workspace/configuration`
- Result (tested with Copilot CLI 1.0.116, 2026-11-27): it errors with a generic settings answer, reports diagnostics only through pull requests that Copilot CLI doesn't send, and never starts next to `typescript`, because Copilot CLI uses one server per file extension
- Status: resolved; the `eslint` row is commented out, see D10 in `arch-decisions.md`
