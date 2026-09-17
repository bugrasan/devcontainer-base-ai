#!/bin/bash
# Image entrypoint for plain 'docker run': bring up sshd, then hand over to the
# command.
#
# A dev container does NOT come through here. The Dev Containers CLI replaces
# the image entrypoint with its own keep-alive command, which is why the
# template calls sshd-init.sh from postStartCommand instead. Both paths run the
# same script, and it is idempotent, so running both changes nothing.
set -euo pipefail

/usr/local/share/base-sandbox/sshd-init.sh || echo "WARNING: sshd-init.sh failed - continuing without sshd." >&2

exec "$@"
