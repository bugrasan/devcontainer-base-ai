#!/bin/bash
# Global npm packages, installed as root into /usr/local/node.
#
# Same set the 'npm-packages' Feature installed for the :base image, minus the
# Feature machinery. They go into the root-owned Node prefix rather than the
# user's home for two reasons: they stay readable-but-not-writable for the
# sandboxed user, and they survive a named volume being mounted over /home.
# The user's own 'npm install -g' still works without sudo - the Dockerfile
# points their npm prefix at ~/.npm-global.
set -euo pipefail
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

PACKAGES="${1:?package list required}"

log "installing global npm packages: ${PACKAGES}"
# shellcheck disable=SC2086  # deliberate word splitting: one package per argument
npm install -g ${PACKAGES}
# Same layer, so the tens of MB of npm download cache never reach the image.
npm cache clean --force
log "global npm packages installed"
