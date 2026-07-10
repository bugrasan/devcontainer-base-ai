#!/bin/bash

# exit on error
set -e

# variables provided by devcontainer-feature
NPM_PACKAGES="${PACKAGES:-"editorconfig eslint typescript @mermaid-js/mermaid-cli"}"

# The 'install.sh' entrypoint script is always executed as the root user.
# For more details, see https://containers.dev/implementors/features#user-env-var
TARGET_USER="${_REMOTE_USER:-root}"

# npm install -g needs to run as the container's remote user (not root) to
# match how the node Feature sets up a user-writable global prefix - the same
# pattern this repo previously used via a postCreateCommand step of the same
# name, before it moved here.
#
# NOTE: plain 'su' (no '-'/login flag) on purpose - a login shell resets PATH
# to the target user's default profile PATH, discarding the PATH addition the
# node Feature bakes into the image via its own containerEnv, which is what
# makes 'npm' resolvable here in the first place. Confirmed by a real CI
# failure hitting the identical bug in a sibling Feature:
# https://github.com/bugrasan/devcontainers-features/pull/13
# Plain su still sets HOME/USER correctly for the target user.
su "${TARGET_USER}" -c "npm install -g ${NPM_PACKAGES}"

echo 'Done!'
