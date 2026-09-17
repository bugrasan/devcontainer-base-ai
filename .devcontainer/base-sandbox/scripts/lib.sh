#!/bin/bash
# Shared helpers for the base-sandbox build-time installers.
# Sourced, never executed: it only defines functions and must not touch state,
# so each installer sets its own shell options.
#
# Why these exist: base-sandbox installs every tool from a plain Dockerfile
# (no Dev Container Features), so the version resolution, architecture mapping
# and checksum verification that the Features used to provide has to live here.

log() { echo "==> $*"; }
warn() { echo "WARNING: $*" >&2; }
die() {
    echo "ERROR: $*" >&2
    exit 1
}

# Architecture name in the flavour a given upstream uses. Every project spells
# the same two architectures differently, so ask for the flavour by name
# instead of scattering 'uname -m' cases across the installers.
#   deb    -> amd64    | arm64     (Debian, gh, otelcol, superfile)
#   node   -> x64      | arm64     (nodejs.org, copilot-cli)
#   uname  -> x86_64   | aarch64   (herdr)
arch_for() {
    local flavour="${1:?flavour required}" machine
    machine="$(uname -m)"
    case "${machine}:${flavour}" in
        x86_64:deb | amd64:deb) echo amd64 ;;
        x86_64:node | amd64:node) echo x64 ;;
        x86_64:uname | amd64:uname) echo x86_64 ;;
        aarch64:deb | arm64:deb) echo arm64 ;;
        aarch64:node | arm64:node) echo arm64 ;;
        aarch64:uname | arm64:uname) echo aarch64 ;;
        x86_64:* | amd64:* | aarch64:* | arm64:*) die "unknown arch flavour '${flavour}'" ;;
        *) die "unsupported architecture '${machine}' - base-sandbox builds linux amd64 and arm64 only." ;;
    esac
}

# GitHub's API rate-limits anonymous callers hard on shared CI runners. The
# build passes a token as a BuildKit secret (never a build arg, which would be
# readable in the image history); use it when present.
github_token() {
    if [ -r /run/secrets/github_token ]; then
        tr -d '\n' < /run/secrets/github_token
    else
        printf '%s' "${GITHUB_TOKEN:-}"
    fi
}

# Latest release tag of a GitHub repo, e.g. 'v2.81.0'.
# Two independent paths, because each fails in a way the other survives:
#   1. the REST API - exact, but rate-limited without a token
#   2. the /releases/latest redirect - no rate limit, but returns only the tag
resolve_latest_tag() {
    local repo="${1:?owner/repo required}" token tag
    token="$(github_token)"

    if [ -n "${token}" ]; then
        tag="$(curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
            -H "Authorization: Bearer ${token}" \
            -H "Accept: application/vnd.github+json" \
            "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null |
            grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
        [ -n "${tag}" ] && {
            echo "${tag}"
            return 0
        }
    fi

    tag="$(curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 -o /dev/null \
        -w '%{url_effective}' "https://github.com/${repo}/releases/latest" 2>/dev/null |
        sed -E 's|.*/tag/||' || true)"
    [ -n "${tag}" ] && [ "${tag}" != "https://github.com/${repo}/releases/latest" ] && {
        echo "${tag}"
        return 0
    }

    tag="$(curl -fsSL --retry 3 --connect-timeout 10 --max-time 30 \
        -H "Accept: application/vnd.github+json" \
        "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null |
        grep -m1 '"tag_name"' | sed -E 's/.*"tag_name"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/' || true)"
    [ -n "${tag}" ] && {
        echo "${tag}"
        return 0
    }

    die "could not resolve the latest release tag of ${repo}."
}

# Highest semver tag of a repo that publishes tags but no GitHub releases.
resolve_latest_git_tag() {
    local repo_url="${1:?repo url required}" tag
    tag="$(git ls-remote --tags --refs "${repo_url}" 2>/dev/null |
        sed -E 's|.*refs/tags/||' | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' |
        sort -V | tail -n1 || true)"
    [ -n "${tag}" ] || die "could not resolve the latest tag of ${repo_url}."
    echo "${tag}"
}

download() {
    local url="${1:?url required}" out="${2:?output path required}"
    curl -fsSL --retry 3 --connect-timeout 10 --max-time 300 -o "${out}" "${url}" ||
        die "could not download ${url}"
}

# Fail the build on a checksum mismatch - a silently substituted binary is the
# one failure mode a sandbox image must never ship.
verify_sha256() {
    local file="${1:?file required}" expected="${2:?expected sha256 required}" actual
    actual="$(sha256sum < "${file}" | awk '{ print $1 }')"
    [ "${actual}" = "${expected}" ] ||
        die "checksum mismatch for ${file}: expected ${expected}, got ${actual}"
    log "verified SHA-256 ${expected}"
}

# Run a command as the unprivileged container user. base-sandbox ships no sudo,
# so this is the only privilege transition in the build, and it only ever goes
# root -> user.
as_user() {
    local user="${1:?user required}"
    shift
    su - "${user}" -c "$*"
}

# Verify a download against an upstream 'sha256  filename' checksums file.
# A mismatch is fatal; an unreachable or entry-less checksums file is only a
# warning, because upstreams add, rename and drop these files between releases
# and a weekly rebuild must not break on that. The two cases are reported
# differently on purpose - whoever reads the log needs to tell them apart.
verify_from_checksums_file() {
    local file="${1:?file required}" asset="${2:?asset name required}" url="${3:?checksums url required}"
    local sums expected
    sums="$(mktemp)"
    if ! curl -fsSL --retry 3 --connect-timeout 10 --max-time 60 -o "${sums}" "${url}" 2>/dev/null; then
        warn "checksums file ${url} was unreachable - ${asset} installed UNVERIFIED (network failure, not a missing upstream checksum)."
        rm -f "${sums}"
        return 0
    fi
    expected="$(awk -v a="${asset}" '$2 == a || $2 == "*" a { print $1; exit }' "${sums}")"
    rm -f "${sums}"
    if [ -z "${expected}" ]; then
        warn "upstream publishes no SHA-256 for ${asset} - installed UNVERIFIED."
        return 0
    fi
    verify_sha256 "${file}" "${expected}"
}
