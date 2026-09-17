#!/bin/bash
# Delete the VS Code sockets and helper scripts that reach back out of the
# container, then keep deleting them for a few minutes.
#
# VS Code drops these into /tmp when it attaches. Each one is a way out of the
# sandbox: the IPC sockets execute commands in the host VS Code process, the
# git ones hand over the host's git credentials, and the ssh-auth socket is the
# host's SSH agent. A coding agent with a shell can use all three.
#
# The repeat passes exist because they are not all created at once: some appear
# only when the IDE finishes attaching, after postStartCommand has run.
set -euo pipefail

PASSES="${HARDEN_SWEEP_PASSES:-10}"
INTERVAL="${HARDEN_SWEEP_INTERVAL:-30}"
LOGFILE="${HARDEN_SWEEP_LOG:-${HOME}/.base-sandbox-harden.log}"

sweep() {
    find /tmp -maxdepth 3 \( \
        -name 'vscode-ssh-auth-*.sock' \
        -o -name 'vscode-ipc-*.sock' \
        -o -name 'vscode-git-*.sock' \
        -o -name 'vscode-remote-containers-ipc-*.sock' \
        -o -name 'vscode-remote-containers-server-*.js' \
        -o -name 'vscode-remote-containers-*.js' \
        \) -delete 2> /dev/null || true
}

sweep
echo "[harden-runtime] $(date -u +%FT%TZ) initial sweep done" >> "${LOGFILE}" 2>/dev/null || true

# Detached so the container's start-up is not held up for PASSES*INTERVAL
# seconds - postStartCommand waits for whatever still holds its stdout.
if [ "${PASSES}" -gt 1 ]; then
    (
        for _ in $(seq 2 "${PASSES}"); do
            sleep "${INTERVAL}"
            sweep
        done
        echo "[harden-runtime] $(date -u +%FT%TZ) background sweeps done" >> "${LOGFILE}" 2>/dev/null || true
    ) > /dev/null 2>&1 < /dev/null &
fi
