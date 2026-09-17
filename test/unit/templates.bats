#!/usr/bin/env bats
# Parses each Dev Container Template the way a consumer would: substitute the
# option defaults, then let the Dev Containers CLI read the result. Catches the
# JSONC mistakes a plain 'jq' cannot - a stray comma inside a comment, an option
# placeholder left in a numeric position, a key the schema does not know.

setup() {
    REPO_ROOT="${BATS_TEST_DIRNAME}/../.."
    RENDER="${BATS_TEST_DIRNAME}/render-template.sh"
    PARSE="${BATS_TEST_DIRNAME}/parse-jsonc.js"
}

# 'devcontainer read-configuration' shells out to 'docker ps' before it reads
# anything, so these tests need a live daemon. The JSONC test below does not,
# and is the one that still runs on a machine without Docker.
needs_cli() {
    command -v devcontainer > /dev/null || skip "the @devcontainers/cli is not installed"
    docker ps -q > /dev/null 2>&1 || skip "no running Docker daemon"
}

read_config() {
    needs_cli
    local rendered
    rendered="$("${RENDER}" "$1")"
    devcontainer read-configuration --workspace-folder "${rendered}" 2>&1
}

@test "base-sandbox-template renders and parses" {
    run read_config "${REPO_ROOT}/src/base-sandbox-template"
    [ "$status" -eq 0 ]
}

@test "base-ai template still renders and parses" {
    run read_config "${REPO_ROOT}/src/base-ai"
    [ "$status" -eq 0 ]
}

@test "the repo's own devcontainer.json parses" {
    needs_cli
    run devcontainer read-configuration --workspace-folder "${REPO_ROOT}"
    [ "$status" -eq 0 ]
}

@test "base-sandbox-template leaves no unsubstituted option placeholder" {
    rendered="$("${RENDER}" "${REPO_ROOT}/src/base-sandbox-template")"
    run grep -r 'templateOption:' "${rendered}/.devcontainer"
    [ "$status" -ne 0 ]
}

@test "base-sandbox-template pins the base-sandbox image" {
    needs_cli
    rendered="$("${RENDER}" "${REPO_ROOT}/src/base-sandbox-template")"
    config="$(devcontainer read-configuration --workspace-folder "${rendered}" |
        grep -o '"image":"[^"]*"' | head -n1)"
    [[ "${config}" == *"devcontainer-base-ai/base-sandbox:latest"* ]]
}

@test "base-sandbox-template drops all capabilities and new privileges" {
    needs_cli
    rendered="$("${RENDER}" "${REPO_ROOT}/src/base-sandbox-template")"
    out="$(devcontainer read-configuration --workspace-folder "${rendered}")"
    [[ "${out}" == *"--cap-drop=ALL"* ]]
    [[ "${out}" == *"no-new-privileges"* ]]
}

@test "base-sandbox-template clears every host handle in remoteEnv" {
    needs_cli
    rendered="$("${RENDER}" "${REPO_ROOT}/src/base-sandbox-template")"
    out="$(devcontainer read-configuration --workspace-folder "${rendered}")"
    for var in SSH_AUTH_SOCK GPG_AGENT_INFO BROWSER VSCODE_IPC_HOOK_CLI \
        VSCODE_GIT_IPC_HANDLE GIT_ASKPASS VSCODE_GIT_ASKPASS_MAIN \
        VSCODE_GIT_ASKPASS_NODE VSCODE_GIT_ASKPASS_EXTRA_ARGS \
        REMOTE_CONTAINERS_IPC REMOTE_CONTAINERS_SOCKETS \
        REMOTE_CONTAINERS_DISPLAY_SOCK WAYLAND_DISPLAY DISPLAY; do
        [[ "${out}" == *"\"${var}\""* ]] || {
            echo "remoteEnv does not mention ${var}"
            return 1
        }
    done
}

@test "base-sandbox-template never mounts the private SSH key" {
    run grep -E 'id_ed25519[^.]' "${REPO_ROOT}/src/base-sandbox-template/.devcontainer/devcontainer.json"
    [ "$status" -ne 0 ]
}

# Runs everywhere, Docker or not: the same JSONC parser VS Code uses, which is
# what catches a stray comma or an unquoted placeholder in these files.
@test "every devcontainer.json in the repo is valid JSONC" {
    for t in "${REPO_ROOT}/src/base-sandbox-template" "${REPO_ROOT}/src/base-ai"; do
        rendered="$("${RENDER}" "${t}")"
        run node "${PARSE}" "${rendered}/.devcontainer/devcontainer.json"
        [ "$status" -eq 0 ]
    done
    for f in "${REPO_ROOT}/.devcontainer/devcontainer.json" "${REPO_ROOT}/.devcontainer/base/devcontainer.json"; do
        run node "${PARSE}" "${f}"
        [ "$status" -eq 0 ]
    done
}

@test "every devcontainer-template.json is valid JSON" {
    for f in "${REPO_ROOT}"/src/*/devcontainer-template.json; do
        run jq -e . "${f}"
        [ "$status" -eq 0 ]
    done
}
