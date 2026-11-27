#!/bin/bash

# exit on error
set -e

# variables provided by devcontainer-feature (booleans arrive as "true"/"false")
COPILOT_LSP_PLUGINS="${COPILOTLSPPLUGINS:-true}"
CLAUDE_LSP_PLUGINS="${CLAUDELSPPLUGINS:-true}"
CLAUDE_LSP_BIAS="${CLAUDELSPBIAS:-true}"

# install.sh always runs as root; the config belongs to the container's user.
# https://containers.dev/implementors/features#user-env-var
TARGET_USER="${_REMOTE_USER:-root}"
TARGET_HOME="${_REMOTE_USER_HOME:-/root}"

# Self-owned local plugin marketplace, root-owned and read-only for the user.
# It must stay in the image: Copilot CLI loads plugins live from this folder.
# BASE_AI_LSP_DIR overrides the path for local tests only.
MARKETPLACE="base-ai-lsp"
MARKETPLACE_DIR="${BASE_AI_LSP_DIR:-/usr/local/share/${MARKETPLACE}}"
# Plugin version: keep in sync with this Feature's version.
PLUGIN_VERSION="2.0.0"
AUTHOR="devcontainer-base-ai"

# One row per language server; each row becomes the plugin "<id>-lsp".
# Fields: id|agents|command|args|extensions (".ext:languageId", space-separated)
# agents: "all" = Claude Code and Copilot CLI; "copilot" = Copilot CLI only.
# The binaries come from the npm-packages and lsp-servers Features.
SERVERS=(
    "bash|all|bash-language-server|start|.sh:shellscript .bash:shellscript"
    # yaml-language-server: online schema fetch (default kept)
    # It can download the SchemaStore catalog (~560K, ~1600 schemas) from
    # https://www.schemastore.org/api/json/catalog.json, then each matching
    # schema on demand. Schemas add validation, completion, and hover for
    # known files (GitHub workflows, compose, ...); without them yaml still
    # gets syntax checks and symbols.
    # The server applies its yaml settings, and starts the fetch, only when
    # the client sends workspace/didChangeConfiguration (2.0.0,
    # pullConfiguration in settingsHandlers.js). Copilot CLI 1.0.116 does not
    # send it: no fetch and no schema validation there (tested 2026-11-27).
    # Claude Code sends its "settings" field that way (fetch unverified).
    # Alternatives for a sandboxed or offline container (tested with
    # yaml-language-server 2.0.0, 2026-11-27):
    #   1. Block it: add "env": {"HTTPS_PROXY": "http://127.0.0.1:9",
    #      "HTTP_PROXY": "http://127.0.0.1:9"} to the yaml server in both
    #      manifests. Matters only for clients that trigger the fetch
    #      (Claude Code, unverified). Workaround.
    #   2. Bake selected schemas: download them at build time, set
    #      yaml.schemaStore.enable=false and map them with yaml.schemas
    #      ("file:///.../schema.json": "<glob>"). Needs the agent to send yaml
    #      settings: Claude Code "settings" only (unverified); Copilot CLI
    #      has no settings field.
    #   3. Local catalog: serve a catalog with file:// schema URLs from
    #      http://127.0.0.1 and point yaml.schemaStore.url at it. A file://
    #      catalog URL is ignored silently. Same settings limit as 2, plus a
    #      running local web server.
    # Initialization options do not turn the fetch off; the server pulls its
    # settings from the client through workspace/configuration.
    "yaml|all|yaml-language-server|--stdio|.yaml:yaml .yml:yaml"
    "json|all|vscode-json-language-server|--stdio|.json:json .jsonc:jsonc"
    "html|all|vscode-html-language-server|--stdio|.html:html .htm:html"
    "css|all|vscode-css-language-server|--stdio|.css:css .scss:scss .less:less"
    # Not wired: Copilot CLI starts one server per file extension, eslint
    # shares .js/.ts with typescript, has no symbols, and needs VS Code
    # settings. vscode-langservers-extracted stays for json, html, and css.
    # "eslint|all|vscode-eslint-language-server|--stdio|.js:javascript .jsx:javascriptreact .mjs:javascript .cjs:javascript .ts:typescript .tsx:typescriptreact"
    # Both agents map file extensions, not file names: a plain "Dockerfile"
    # does not match, only "*.dockerfile".
    "dockerfile|all|docker-langserver|--stdio|.dockerfile:dockerfile"
    "markdown|all|marksman|server|.md:markdown .markdown:markdown"
    "toml|all|taplo|lsp stdio|.toml:toml"
    # Claude Code gets pyright from claude-plugins-official (claude-code
    # Feature); Copilot CLI cannot add that marketplace.
    "pyright|copilot|pyright-langserver|--stdio|.py:python .pyi:python"
    # TypeScript 7 (typescript-go, the npm "typescript" package) ships its
    # own server, "tsc --lsp --stdio", and no lib/tsserver.js, which
    # typescript-language-server (and the official typescript-lsp plugin)
    # needs; see typescript-language-server issue #1110.
    "typescript|all|tsc|--lsp --stdio|.ts:typescript .tsx:typescriptreact .mts:typescript .cts:typescript .js:javascript .jsx:javascriptreact .mjs:javascript .cjs:javascript"
    # Deferred: enable together with the matching block in lsp-servers.
    # For Claude Code, add jdtls-lsp@claude-plugins-official to the
    # claude-code Feature's lspPlugins instead (see devcontainer.json).
    # "jdtls|copilot|jdtls||.java:java"
    # "terraform|all|terraform-ls|serve|.tf:terraform .tfvars:terraform-vars"
    # "xml|all|lemminx||.xml:xml .xsd:xml .xsl:xml .xslt:xml"
)

# Run a command as the target user through a login shell (HOME and PATH
# resolve as at runtime); run it directly if we already are that user,
# which local tests use.
run_as_user() {
    if [ "$(id -un)" = "${TARGET_USER}" ]; then
        bash -c "$1"
    else
        su - "${TARGET_USER}" -c "$1"
    fi
}

# Stop with a clear message if a CLI this script calls is missing.
require_cli() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "ERROR: '$1' not found; $2." >&2
        exit 1
    fi
}

# Write the marketplace: one plugin per server, two manifests per plugin.
# Claude Code reads .claude-plugin/plugin.json ("extensionToLanguage",
# strict schema); Copilot CLI prefers .github/plugin/plugin.json and
# requires "fileExtensions". Neither accepts the other's key.
# Sets PLUGINS, a JSON list of {name, agents, description}; the installs
# below pick from it.
PLUGINS='[]'
generate_marketplace() {
    local row id agents cmd args exts name dir ext_map args_json desc target
    rm -rf "${MARKETPLACE_DIR}"
    mkdir -p "${MARKETPLACE_DIR}/.claude-plugin"
    for row in "${SERVERS[@]}"; do
        IFS='|' read -r id agents cmd args exts <<< "${row}"
        name="${id}-lsp"
        dir="${MARKETPLACE_DIR}/plugins/${name}"
        mkdir -p "${dir}/.claude-plugin" "${dir}/.github/plugin"
        # shellcheck disable=SC2086 # split the space-separated list
        ext_map="$(printf '%s\n' ${exts} | jq -Rn \
            '[inputs | split(":") | {(.[0]): .[1]}] | add')"
        args_json="$(jq -cn --arg a "${args}" \
            '$a | split(" ") | map(select(length > 0))')"
        desc="${cmd} language server for $(jq -r \
            'keys_unsorted | join(", ")' <<< "${ext_map}")"
        for target in claude copilot; do
            jq -n --arg name "${name}" --arg version "${PLUGIN_VERSION}" \
                --arg author "${AUTHOR}" --arg id "${id}" --arg cmd "${cmd}" \
                --argjson args "${args_json}" --argjson map "${ext_map}" \
                --arg key "$([ "${target}" = claude ] \
                    && echo extensionToLanguage || echo fileExtensions)" \
                --arg desc "${desc}" \
                '{name: $name, version: $version, description: $desc,
                  author: {name: $author},
                  lspServers: {($id): {command: $cmd, args: $args,
                                       ($key): $map}}}' \
                > "${dir}/$([ "${target}" = claude ] \
                    && echo .claude-plugin || echo .github/plugin)/plugin.json"
        done
        PLUGINS="$(jq -c --arg name "${name}" --arg agents "${agents}" \
            --arg desc "${desc}" \
            '. + [{name: $name, agents: $agents, description: $desc}]' \
            <<< "${PLUGINS}")"
    done
    jq -n --arg name "${MARKETPLACE}" --arg author "${AUTHOR}" \
        --argjson plugins "${PLUGINS}" \
        '{name: $name, owner: {name: $author},
          description: "Language server plugins baked into the base image",
          plugins: [$plugins[] | {name, source: ("./plugins/" + .name),
                                  description}]}' \
        > "${MARKETPLACE_DIR}/.claude-plugin/marketplace.json"
    if [ "$(id -u)" = 0 ]; then
        chown -R root:root "${MARKETPLACE_DIR}"
    fi
    chmod -R u=rwX,go=rX "${MARKETPLACE_DIR}"
}

# Plugin names for one agent: "all" rows, plus "copilot" rows for Copilot.
plugins_for() {
    jq -r --arg agent "$1" \
        '.[] | select(.agents == "all" or .agents == $agent) | .name' \
        <<< "${PLUGINS}"
}

# Fail early, before anything is written, if a needed CLI is missing.
if [ "${COPILOT_LSP_PLUGINS}" = "true" ]; then
    require_cli copilot "install the ghcr.io/devcontainers/features/copilot-cli Feature first"
fi
if [ "${CLAUDE_LSP_PLUGINS}" = "true" ]; then
    require_cli claude "install the ghcr.io/bugrasan/devcontainers-features/claude-code Feature first"
fi
if [ "${COPILOT_LSP_PLUGINS}" = "true" ] \
    || [ "${CLAUDE_LSP_PLUGINS}" = "true" ]; then
    require_cli jq "install jq (the base image's apt list has it)"
fi

# Claude Code reads ~/.claude/CLAUDE.md as user memory - a soft bias, not a switch.
if [ "${CLAUDE_LSP_BIAS}" = "true" ]; then
    mkdir -p "${TARGET_HOME}/.claude"
    cat > "${TARGET_HOME}/.claude/CLAUDE.md" <<'EOM'
Before code navigation, check whether an LSP server is running. If so, prefer LSP operations (go-to-definition, find-references, hover) over Grep/Read when resolving symbols and types.
EOM
fi

# Hand ownership of anything we created to the remote user (we wrote it as
# root) before the plugin installs below write into the same folders.
if [ "${TARGET_USER}" != "root" ] && [ "$(id -u)" = 0 ]; then
    chown -R "${TARGET_USER}" "${TARGET_HOME}/.copilot" "${TARGET_HOME}/.claude" 2>/dev/null || true
fi

if [ "${COPILOT_LSP_PLUGINS}" = "true" ] \
    || [ "${CLAUDE_LSP_PLUGINS}" = "true" ]; then
    generate_marketplace
fi

# Install as the user (writes the user's settings, no login needed).
# Fail hard: every input is local, so an error is a real defect and must
# not ship an image with missing language servers.
if [ "${COPILOT_LSP_PLUGINS}" = "true" ]; then
    run_as_user "copilot plugin marketplace add '${MARKETPLACE_DIR}'"
    for plugin in $(plugins_for copilot); do
        run_as_user "copilot plugin install '${plugin}@${MARKETPLACE}'"
    done
    # Drop what the first run left behind: build logs, the ~280M unpacked
    # runtime (unpacked again on first use), and device IDs, which must be
    # unique per container.
    rm -rf "${TARGET_HOME}/.copilot/logs" "${TARGET_HOME}/.cache/copilot"
    rm -f "${TARGET_HOME}/.cache/Microsoft/DeveloperTools/deviceid" \
        "${TARGET_HOME}/.local/state/gh/device-id"
fi

if [ "${CLAUDE_LSP_PLUGINS}" = "true" ]; then
    run_as_user \
        "claude plugin marketplace add '${MARKETPLACE_DIR}' --scope user"
    for plugin in $(plugins_for claude); do
        run_as_user \
            "claude plugin install '${plugin}@${MARKETPLACE}' --scope user"
    done
fi

echo 'Done!'
