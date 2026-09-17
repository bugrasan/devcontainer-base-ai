#!/bin/bash
# Render a Dev Container Template into a throwaway workspace by substituting
# every ${templateOption:x} with its default, the way 'devcontainer templates
# apply' would. Prints the workspace path.
#
# Usage: render-template.sh <src/template-dir> [<output-dir>]
set -euo pipefail

SRC="${1:?template directory required}"
OUT="${2:-$(mktemp -d)}"

manifest="${SRC}/devcontainer-template.json"
[ -f "${manifest}" ] || {
    echo "ERROR: no devcontainer-template.json in ${SRC}" >&2
    exit 1
}

mkdir -p "${OUT}"
cp -r "${SRC}/.devcontainer" "${OUT}/"

# One sed expression per option. Values are plain strings here (ports, booleans),
# so no escaping beyond '/' is needed.
while IFS=$'\t' read -r key value; do
    escaped="${value//\//\\/}"
    find "${OUT}/.devcontainer" -type f -print0 |
        xargs -0 sed -i "s/\${templateOption:${key}}/${escaped}/g"
done < <(jq -r '.options // {} | to_entries[] | [.key, (.value.default // "")] | @tsv' "${manifest}")

echo "${OUT}"
