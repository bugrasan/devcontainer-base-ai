#!/bin/bash
# Decide which GHCR package versions to delete. Pure function: it reads the
# version list on stdin and writes to stdout, and talks to nothing. The network
# side lives in prune-ghcr-versions.sh, so this part can be tested.
#
# Usage:
#   select-prunable-versions.sh [--mode ids|kept-tags] \
#       <keep> <protected-tags> <protected-digests> [<tag-pattern>]
#
#   --mode ids        (default) print the version ids that are safe to delete
#   --mode kept-tags  print the release tags that will be kept - the caller
#                     needs these to look up the per-architecture children that
#                     must be protected along with them
#   keep              how many release versions to keep, newest first
#   protected-tags    space-separated tags that are never deleted
#   protected-digests space-separated digests that are never deleted, which is
#                     how the children of a kept multi-arch manifest survive:
#                     they carry no tags of their own
#   tag-pattern       regex identifying a release version (default: 20260917-abc1234)
#
# stdin  a JSON array of GHCR versions: [{id, name, created_at, metadata:{container:{tags:[]}}}]
set -euo pipefail

MODE=ids
if [ "${1-}" = "--mode" ]; then
    MODE="${2:?mode required after --mode}"
    shift 2
fi
case "${MODE}" in
    ids | kept-tags) ;;
    *)
        echo "ERROR: unknown mode '${MODE}' - use 'ids' or 'kept-tags'." >&2
        exit 2
        ;;
esac

KEEP="${1:?keep count required}"
PROTECTED_TAGS="${2-}"
PROTECTED_DIGESTS="${3-}"
# Not a "${4:-default}" one-liner: the braces in the regex would close the
# parameter expansion early and silently hand jq a pattern that matches nothing.
TAG_PATTERN="${4-}"
[ -n "${TAG_PATTERN}" ] || TAG_PATTERN='^[0-9]{8}-[0-9a-f]{7}$'

[ "${KEEP}" -ge 1 ] || {
    echo "ERROR: keep must be at least 1 - refusing to delete every version." >&2
    exit 1
}

jq -r \
    --argjson keep "${KEEP}" \
    --arg mode "${MODE}" \
    --arg protected_tags "${PROTECTED_TAGS}" \
    --arg protected_digests "${PROTECTED_DIGESTS}" \
    --arg tag_pattern "${TAG_PATTERN}" '
    ($protected_tags     | split(" ") | map(select(length > 0))) as $keep_tags
    | ($protected_digests | split(" ") | map(select(length > 0))) as $keep_digests

    # Release versions: the dated tags this workflow publishes, newest first by
    # creation time - a rebuilt tag keeps its name but not its position.
    | ( [ .[] | select(any((.metadata.container.tags // [])[]; test($tag_pattern))) ]
        | sort_by(.created_at) | reverse
        | .[0:$keep] ) as $kept

    | if $mode == "kept-tags" then
        $kept[] | (.metadata.container.tags // [])[] | select(test($tag_pattern))
      else
        ($kept | map(.id)) as $kept_ids

        # Bind every field before testing it: inside a pipe "." is the
        # left-hand side, so an unbound .id would resolve against the wrong
        # object.
        | .[]
        | .id as $id
        | (.name // "") as $digest
        | (.metadata.container.tags // []) as $tags
        | select(
            (($kept_ids | index($id)) == null)
            and (([ $tags[] | select(. as $t | $keep_tags | index($t) != null) ] | length) == 0)
            and (($keep_digests | index($digest)) == null)
          )
        | $id
      end
'
