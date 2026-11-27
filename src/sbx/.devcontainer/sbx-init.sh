#!/bin/sh
# Prepare the host side before compose starts; runs on the host, never in a container.
# Called by devcontainer.json (initializeCommand) and pm-comp.sh; safe to run again.
# - .env: create it from .env.example on the first run, then update only the PROJECT= line
#   (README.md, AD-02); all other lines are yours
# - .git/ and .copilot/: create empty folders if missing; compose mounts them read-only and
#   would otherwise fail (README.md, AD-03)
# POSIX sh for Linux and macOS: no sed -i, no GNU-only options
set -eu

cd "$(dirname "$0")"
root=$(cd .. && pwd)
project=$(basename "$root")

# The name ends up in a container path, a compose variable, and VS Code's workspaceFolder
case $project in
  ''|*[!A-Za-z0-9._-]*)
    echo "sbx-init.sh: project folder name '$project' may contain only A-Z, a-z, 0-9, '.', '_', and '-'" >&2
    exit 1 ;;
esac

if [ ! -f .env ]; then
  # Compose project name: lowercase letters, digits, '-', and '_'; must start with a letter or digit
  p=sbx-$(printf '%s' "$project" | tr '[:upper:]' '[:lower:]' | tr -c 'a-z0-9_-' '-')
  sed -e "s|^P=.*|P=$p|" \
      -e "s|^AGENT_UID=.*|AGENT_UID=$(id -u)|" \
      -e "s|^AGENT_GID=.*|AGENT_GID=$(id -g)|" \
      .env.example > .env
  echo "sbx-init.sh: created .devcontainer/.env (P=$p); edit it if needed"
fi

if grep -q '^PROJECT=' .env; then
  if ! grep -qxF "PROJECT=$project" .env; then
    tmp=$(mktemp .env.XXXXXX)
    sed "s|^PROJECT=.*|PROJECT=$project|" .env > "$tmp"
    cat "$tmp" > .env
    rm -f "$tmp"
  fi
else
  # Add a line break first if the file does not end with one
  [ ! -s .env ] || [ "$(tail -c 1 .env | wc -l)" -eq 1 ] || echo >> .env
  echo "PROJECT=$project" >> .env
fi

if [ -f ../.git ]; then
  echo "sbx-init.sh: warning: .git is a file (git worktree or submodule); git does not work inside the sandbox (README.md, Limits)" >&2
elif [ ! -e ../.git ]; then
  mkdir ../.git
  echo "sbx-init.sh: created an empty .git/ placeholder; 'git init' on the host still works"
fi

[ -e ../.copilot ] || mkdir ../.copilot
