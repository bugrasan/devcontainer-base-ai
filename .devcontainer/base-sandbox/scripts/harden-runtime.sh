#!/bin/bash
# Delete the VS Code sockets and helper scripts that reach back out of the
# container, then keep deleting them for a few minutes.
#
# VS Code drops these into /tmp when it attaches. Each one is a way out of the
# sandbox: the IPC sockets execute commands in the host VS Code process, the
# git ones hand over the host's git credentials, and the ssh-auth socket is the
# host's SSH agent. A coding agent with a shell can use all three.
#
# The sweep repeats, and by default never stops, because these are not created
# once: some appear only when the IDE finishes attaching, after postStartCommand
# has run, and VS Code recreates them on every window reload or reconnect.
#
# 'vscode-remote-containers-server-*.js' is the dev-containers extension's own
# in-container server script, and deleting it is deliberate - it is the channel
# the 'code' CLI uses. Set HARDEN_SWEEP_PASSES to a positive number for a
# time-boxed sweep instead.
set -euo pipefail

# 0 passes means "keep sweeping for as long as the container runs", which is the
# default: VS Code recreates these sockets whenever a window reconnects or
# reloads, so a sweep that stops after N passes is a control with an expiry date.
PASSES="${HARDEN_SWEEP_PASSES:-0}"
INTERVAL="${HARDEN_SWEEP_INTERVAL:-30}"
LOGFILE="${HARDEN_SWEEP_LOG:-${HOME}/.base-sandbox-harden.log}"

# Both come from the environment and are used in arithmetic below, where a
# non-numeric value would abort under 'set -e' and take postStartCommand with it.
case "${PASSES}" in *[!0-9]*) PASSES=0 ;; esac
case "${INTERVAL}" in *[!0-9]* | '') INTERVAL=30 ;; esac
[ "${INTERVAL}" -ge 1 ] || INTERVAL=30

sweep() {
    find /tmp -maxdepth 3 \( \
        -name 'vscode-ssh-auth-*.sock' \
        -o -name 'vscode-ipc-*.sock' \
        -o -name 'vscode-git-*.sock' \
        -o -name 'vscode-remote-containers-ipc-*.sock' \
        -o -name 'vscode-remote-containers-server-*.js' \
        \) -delete 2> /dev/null || true
}

sweep
echo "[harden-runtime] $(date -u +%FT%TZ) initial sweep done" >> "${LOGFILE}" 2>/dev/null || true

# Detached, with fd 0/1/2 closed off: postStartCommand waits for whatever still
# holds its stdout, so an attached loop would stall the container's start-up.
(
    if [ "${PASSES}" -eq 0 ]; then
        while true; do
            sleep "${INTERVAL}"
            sweep
        done
    else
        for _ in $(seq 2 "${PASSES}"); do
            sleep "${INTERVAL}"
            sweep
        done
        echo "[harden-runtime] $(date -u +%FT%TZ) background sweeps done" >> "${LOGFILE}" 2>/dev/null || true
    fi
) > /dev/null 2>&1 < /dev/null &
