#!/bin/bash

# exit on error
set -e

# variables provided by devcontainer-feature
NPM_PACKAGES="${PACKAGES:-"editorconfig eslint typescript pyright"}"

# The 'install.sh' entrypoint script is always executed as the root user.
# For more details, see https://containers.dev/implementors/features#user-env-var
TARGET_USER="${_REMOTE_USER:-root}"

# 'installsAfter: node' only guarantees this Feature's RUN layer executes
# after node's RUN layer (so node's files exist on disk) - it does NOT make
# node's own containerEnv (its PATH/NVM_DIR additions) active during a
# sibling Feature's install.sh at build time; that containerEnv only takes
# effect in the final container's runtime environment. Confirmed by a real CI
# failure hitting the identical bug in a sibling Feature:
# https://github.com/bugrasan/devcontainers-features/pull/13
#
# So node/npm must be resolved explicitly here, using the same stable
# 'current' version symlink the node Feature's own containerEnv references:
# https://github.com/devcontainers/features/blob/main/src/node/devcontainer-feature.json
NVM_DIR="${NVM_DIR:-/usr/local/share/nvm}"
NODE_BIN_DIR="${NVM_DIR}/current/bin"

# npm install -g needs to run as the container's remote user (not root) to
# match how the node Feature sets up a user-writable global prefix - the same
# pattern this repo previously used via a postCreateCommand step of the same
# name, before it moved here.
#
# `npm cache clean --force` runs in the same command (same image layer) so the
# ~tens-of-MB npm download cache never gets committed into the layer.
su "${TARGET_USER}" -c "export PATH='${NODE_BIN_DIR}:${PATH}'; npm install -g ${NPM_PACKAGES} && npm cache clean --force"

echo 'Done!'
