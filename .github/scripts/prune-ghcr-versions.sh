#!/bin/bash
# Keep the current release of a GHCR container package plus the two before it,
# and delete everything older - including the untagged per-architecture
# manifests those older releases leave behind.
#
# Usage:
#   prune-ghcr-versions.sh <owner> <package-path> <keep> [--dry-run]
#     owner         GitHub user or org that owns the package
#     package-path  package name as GHCR spells it, e.g. devcontainer-base-ai/base-sandbox
#     keep          how many dated releases to keep (3 = current + 2 past)
#
# Needs GITHUB_TOKEN. A repository GITHUB_TOKEN can read package versions but
# is often refused on DELETE for a USER-owned package; the script says so and
# exits 0 rather than failing a build whose image is already published.
set -euo pipefail

OWNER="${1:?owner required}"
PACKAGE="${2:?package path required}"
KEEP="${3:?keep count required}"
DRY_RUN=false
[ "${4-}" = "--dry-run" ] && DRY_RUN=true

: "${GITHUB_TOKEN:?GITHUB_TOKEN is required}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELECT="${SCRIPT_DIR}/select-prunable-versions.sh"
IMAGE="ghcr.io/${OWNER}/${PACKAGE}"

# The floating tags this workflow rewrites on every build. They are never a
# "version" to keep or delete by age - whatever they point at must survive.
PROTECTED_TAGS="latest latest-linux-amd64 latest-linux-arm64 buildcache-amd64 buildcache-arm64"

# GHCR spells the package path with '/' encoded.
PACKAGE_ENC="${PACKAGE//\//%2F}"
API="https://api.github.com/users/${OWNER}/packages/container/${PACKAGE_ENC}"

api() {
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" "$@"
}

echo "==> listing versions of ${IMAGE}"
versions="$(mktemp)"
page_file="$(mktemp)"
trap 'rm -f "${versions}" "${page_file}"' EXIT
echo '[]' > "${versions}"
for page in 1 2 3 4 5 6 7 8 9 10; do
    if ! api "${API}/versions?per_page=100&page=${page}" > "${page_file}"; then
        echo "::warning::could not list versions of ${PACKAGE} (page ${page}) - skipping retention."
        exit 0
    fi
    [ "$(jq 'length' "${page_file}")" -gt 0 ] || break
    jq -s 'add' "${versions}" "${page_file}" > "${versions}.new" && mv "${versions}.new" "${versions}"
    [ "$(jq 'length' "${page_file}")" -lt 100 ] && break
done
total="$(jq 'length' "${versions}")"
echo "    ${total} version(s) found"
[ "${total}" -gt 0 ] || exit 0

# A multi-arch tag is a manifest list whose per-architecture children are
# separate, untagged versions. Deleting a child breaks the tag, so collect the
# children of every tag that survives this run and protect them explicitly.
echo "==> resolving the children of the tags that stay"
kept_tags="$("${SELECT}" --mode kept-tags "${KEEP}" "${PROTECTED_TAGS}" "" < "${versions}")"
protected_digests=""
for tag in ${PROTECTED_TAGS} ${kept_tags}; do
    # A tag that does not exist yet is normal on a first run.
    jq -e --arg t "${tag}" 'any(.[]; (.metadata.container.tags // []) | index($t))' "${versions}" > /dev/null || continue
    if ! children="$(docker buildx imagetools inspect --raw "${IMAGE}:${tag}" 2> /dev/null |
        jq -r '.manifests[]?.digest' 2> /dev/null)"; then
        echo "::warning::could not inspect ${IMAGE}:${tag} - skipping retention rather than risking its children."
        exit 0
    fi
    [ -n "${children}" ] && protected_digests="${protected_digests} ${children}"
done
echo "    protecting $(echo "${protected_digests}" | wc -w) child manifest(s)"

prunable="$("${SELECT}" "${KEEP}" "${PROTECTED_TAGS}" "${protected_digests}" < "${versions}")"
count="$(echo "${prunable}" | grep -c . || true)"
if [ "${count}" -eq 0 ]; then
    echo "==> nothing to prune (keeping the newest ${KEEP} release(s))"
    exit 0
fi

echo "==> deleting ${count} of ${total} version(s), keeping the newest ${KEEP} release(s) and every floating tag"
jq -r --arg ids "${prunable}" '
    ($ids | split("\n") | map(select(length > 0) | tonumber)) as $del
    | .[] | select(.id | IN($del[]))
    | "    - \(.id) \(.created_at) [\((.metadata.container.tags // []) | join(", "))]"
' "${versions}"

if [ "${DRY_RUN}" = true ]; then
    echo "==> dry run: nothing deleted"
    exit 0
fi

deleted=0
for id in ${prunable}; do
    if api -X DELETE -o /dev/null "${API}/versions/${id}"; then
        deleted=$((deleted + 1))
    else
        echo "::warning::could not delete version ${id} of ${PACKAGE}. A repository GITHUB_TOKEN cannot delete versions of a user-owned package: add a GHCR_PAT secret (a personal access token with 'delete:packages') to enable retention."
        exit 0
    fi
done
echo "==> deleted ${deleted} version(s)"
