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
su - "${TARGET_USER}" -c "npm install -g ${NPM_PACKAGES}"

echo 'Done!'
