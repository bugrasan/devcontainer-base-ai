# shellcheck shell=sh
# Sourced by every BASH shell in the container - do not add anything slow here.
#
# NOT every shell: /bin/sh on Debian is dash, which ignores BASH_ENV and reads
# $ENV only when interactive, so a bare 'sh -c' is not covered. remoteEnv in
# devcontainer.json is what covers that case, by never setting the variables in
# the first place; this file is defence in depth behind it.
#
# VS Code injects these into the terminals and tasks it starts. Each is a
# handle on something outside the container: the host SSH agent, the host GPG
# agent, the host browser, the VS Code CLI IPC channel (arbitrary commands in
# the host VS Code process) and the git credential helpers (the host's
# credentials). remoteEnv in devcontainer.json clears them for processes the
# IDE starts directly; this clears them for every other shell as well,
# including the non-interactive ones a coding agent spawns.
unset SSH_AUTH_SOCK
unset GPG_AGENT_INFO
unset BROWSER
unset VSCODE_IPC_HOOK_CLI
unset VSCODE_GIT_IPC_HANDLE
unset GIT_ASKPASS
unset VSCODE_GIT_ASKPASS_MAIN
unset VSCODE_GIT_ASKPASS_NODE
unset VSCODE_GIT_ASKPASS_EXTRA_ARGS
unset REMOTE_CONTAINERS_IPC
unset REMOTE_CONTAINERS_SOCKETS
unset REMOTE_CONTAINERS_DISPLAY_SOCK
unset WAYLAND_DISPLAY
unset DISPLAY
