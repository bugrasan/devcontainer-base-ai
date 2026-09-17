#!/usr/bin/env bats
# Unit tests for the GHCR retention selection. These run on the host - no
# network, no registry, no Docker - so the rule "current plus two past
# versions" is verified against fixed input rather than against production.

setup() {
    SELECT="${BATS_TEST_DIRNAME}/../../.github/scripts/select-prunable-versions.sh"
    PROTECTED_TAGS="latest latest-linux-amd64 latest-linux-arm64 buildcache-amd64 buildcache-arm64"
}

# Five weekly releases, newest last in the file to prove the sort does the work,
# plus the floating tags and two untagged per-arch children of :latest.
fixture() {
    cat <<'JSON'
[
  {"id": 101, "name": "sha256:aaa1", "created_at": "2026-08-15T06:54:00Z",
   "metadata": {"container": {"tags": ["20260815-1111111"]}}},
  {"id": 102, "name": "sha256:aaa2", "created_at": "2026-08-22T06:54:00Z",
   "metadata": {"container": {"tags": ["20260822-2222222"]}}},
  {"id": 103, "name": "sha256:aaa3", "created_at": "2026-08-29T06:54:00Z",
   "metadata": {"container": {"tags": ["20260829-3333333"]}}},
  {"id": 104, "name": "sha256:aaa4", "created_at": "2026-09-05T06:54:00Z",
   "metadata": {"container": {"tags": ["20260905-4444444"]}}},
  {"id": 105, "name": "sha256:aaa5", "created_at": "2026-09-12T06:54:00Z",
   "metadata": {"container": {"tags": ["20260912-5555555", "latest"]}}},
  {"id": 200, "name": "sha256:bbb1", "created_at": "2026-09-12T06:54:00Z",
   "metadata": {"container": {"tags": ["latest-linux-amd64"]}}},
  {"id": 201, "name": "sha256:bbb2", "created_at": "2026-09-12T06:54:00Z",
   "metadata": {"container": {"tags": ["latest-linux-arm64"]}}},
  {"id": 202, "name": "sha256:ccc1", "created_at": "2026-09-12T06:54:00Z",
   "metadata": {"container": {"tags": ["buildcache-amd64"]}}},
  {"id": 300, "name": "sha256:ddd1", "created_at": "2026-09-12T06:54:00Z",
   "metadata": {"container": {"tags": []}}},
  {"id": 301, "name": "sha256:ddd2", "created_at": "2026-08-15T06:54:00Z",
   "metadata": {"container": {"tags": []}}}
]
JSON
}

@test "keeps the newest three dated releases and deletes the older ones" {
    output="$(fixture | "${SELECT}" 3 "${PROTECTED_TAGS}" "")"
    [ "$(echo "${output}" | grep -cx 101)" -eq 1 ]
    [ "$(echo "${output}" | grep -cx 102)" -eq 1 ]
    for kept in 103 104 105; do
        [ "$(echo "${output}" | grep -cx "${kept}")" -eq 0 ]
    done
}

@test "never deletes a version carrying a protected tag" {
    output="$(fixture | "${SELECT}" 1 "${PROTECTED_TAGS}" "")"
    for protected in 105 200 201 202; do
        [ "$(echo "${output}" | grep -cx "${protected}")" -eq 0 ]
    done
}

@test "deletes untagged versions that nothing protects" {
    output="$(fixture | "${SELECT}" 3 "${PROTECTED_TAGS}" "")"
    [ "$(echo "${output}" | grep -cx 300)" -eq 1 ]
    [ "$(echo "${output}" | grep -cx 301)" -eq 1 ]
}

@test "keeps untagged children of a protected manifest when their digests are passed" {
    output="$(fixture | "${SELECT}" 3 "${PROTECTED_TAGS}" "sha256:ddd1 sha256:ddd2")"
    [ "$(echo "${output}" | grep -cx 300)" -eq 0 ]
    [ "$(echo "${output}" | grep -cx 301)" -eq 0 ]
}

# The form prune-ghcr-versions.sh actually builds: 'imagetools inspect' prints
# one digest per line. An earlier version split on a literal " " and so
# protected nothing, which deleted the per-architecture children of :latest and
# left the tag unpullable.
@test "protects children passed newline-separated, as the caller builds them" {
    output="$(fixture | "${SELECT}" 3 "${PROTECTED_TAGS}" "$(printf ' sha256:ddd1\nsha256:ddd2')")"
    [ "$(echo "${output}" | grep -cx 300)" -eq 0 ]
    [ "$(echo "${output}" | grep -cx 301)" -eq 0 ]
}

@test "protects tags passed newline-separated too" {
    output="$(fixture | "${SELECT}" 1 "$(printf 'latest\nlatest-linux-amd64')" "")"
    [ "$(echo "${output}" | grep -cx 105)" -eq 0 ]
    [ "$(echo "${output}" | grep -cx 200)" -eq 0 ]
}

# Pins the selector's pattern to the tag format the workflow actually builds.
# If either side changes alone, retention silently stops recognising releases.
@test "the tag format the workflow publishes is recognised as a release" {
    tag="$(date -u +%Y%m%d)-0123abc"
    input="$(printf '[{"id": 1, "name": "sha256:x", "created_at": "2026-09-12T06:54:00Z",
             "metadata": {"container": {"tags": ["%s"]}}}]' "${tag}")"
    output="$(echo "${input}" | "${SELECT}" 3 "${PROTECTED_TAGS}" "")"
    [ -z "${output}" ]
    kept="$(echo "${input}" | "${SELECT}" --mode kept-tags 3 "${PROTECTED_TAGS}" "")"
    [ "${kept}" = "${tag}" ]
}

@test "keep=5 with five releases deletes no release" {
    output="$(fixture | "${SELECT}" 5 "${PROTECTED_TAGS}" "")"
    for id in 101 102 103 104 105; do
        [ "$(echo "${output}" | grep -cx "${id}")" -eq 0 ]
    done
}

@test "refuses keep=0 rather than deleting everything" {
    run bash -c "echo '[]' | '${SELECT}' 0 '' ''"
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to delete every version"* ]]
}

@test "an empty version list selects nothing" {
    output="$(echo '[]' | "${SELECT}" 3 "${PROTECTED_TAGS}" "")"
    [ -z "${output}" ]
}

@test "a tag that only looks like a date is not treated as a release" {
    input='[{"id": 1, "name": "sha256:x", "created_at": "2026-09-12T06:54:00Z",
             "metadata": {"container": {"tags": ["2026-09-12"]}}}]'
    output="$(echo "${input}" | "${SELECT}" 3 "${PROTECTED_TAGS}" "")"
    [ "$(echo "${output}" | grep -cx 1)" -eq 1 ]
}

@test "kept-tags mode lists exactly the release tags that survive" {
    output="$(fixture | "${SELECT}" --mode kept-tags 3 "${PROTECTED_TAGS}" "")"
    [ "$(echo "${output}" | sort)" = "$(printf '20260829-3333333\n20260905-4444444\n20260912-5555555\n')" ]
}

@test "kept-tags mode does not list the floating tags" {
    output="$(fixture | "${SELECT}" --mode kept-tags 3 "${PROTECTED_TAGS}" "")"
    refute_tag() { [ "$(echo "${output}" | grep -cx "$1")" -eq 0 ]; }
    refute_tag latest
    refute_tag latest-linux-amd64
    refute_tag buildcache-amd64
}

@test "an unknown mode is rejected" {
    run bash -c "echo '[]' | '${SELECT}' --mode nonsense 3 '' ''"
    [ "$status" -eq 2 ]
}
