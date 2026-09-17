#!/bin/bash
# Release-tarball CLI tools installed system-wide into /usr/local/bin:
# GitHub CLI, OpenTelemetry Collector Contrib, superfile and herdr.
#
# All four ship prebuilt linux amd64/arm64 binaries, so a tarball keeps them
# root-owned and out of the sandboxed user's reach without adding third-party
# apt repositories. This replaces the github-cli Feature and the
# otel-collector-contrib / superfile / herdr Features of the :base image.
set -euo pipefail
# shellcheck source=./lib.sh
. "$(dirname "$0")/lib.sh"

INSTALL_DIR="/usr/local/bin"
TARGET_USER="${1:?target user required}"
TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6)"
TARGET_GROUP="$(id -gn "${TARGET_USER}")"
deb_arch="$(arch_for deb)"

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

# --- GitHub CLI -------------------------------------------------------------
install_github_cli() {
    local tag version asset
    tag="$(resolve_latest_tag cli/cli)"
    version="${tag#v}"
    asset="gh_${version}_linux_${deb_arch}.tar.gz"
    log "installing GitHub CLI ${version} (linux/${deb_arch})"

    download "https://github.com/cli/cli/releases/download/${tag}/${asset}" "${tmpdir}/${asset}"
    verify_from_checksums_file "${tmpdir}/${asset}" "${asset}" \
        "https://github.com/cli/cli/releases/download/${tag}/gh_${version}_checksums.txt"

    tar -xzf "${tmpdir}/${asset}" -C "${tmpdir}"
    install -m 0755 "${tmpdir}/gh_${version}_linux_${deb_arch}/bin/gh" "${INSTALL_DIR}/gh"

    # bash-completion lazy-loads by command name, so this costs nothing at
    # shell start-up and needs no rc-file edit.
    mkdir -p /usr/share/bash-completion/completions /usr/local/share/zsh/site-functions
    "${INSTALL_DIR}/gh" completion -s bash > /usr/share/bash-completion/completions/gh 2>/dev/null ||
        warn "could not generate gh bash completion"
    "${INSTALL_DIR}/gh" completion -s zsh > /usr/local/share/zsh/site-functions/_gh 2>/dev/null ||
        warn "could not generate gh zsh completion"
}

# --- OpenTelemetry Collector Contrib ----------------------------------------
# Binary plus a default OTLP -> Azure Application Insights config. Nothing is
# started: no collector runs and nothing listens on 4317/4318 until someone
# runs it by hand. The connection string is resolved from the environment at
# collector start-up, so it is never baked into the image.
install_otelcol() {
    local tag version asset config="/etc/otelcol-contrib/config.yaml"
    tag="$(resolve_latest_tag open-telemetry/opentelemetry-collector-releases)"
    version="${tag#v}"
    asset="otelcol-contrib_${version}_linux_${deb_arch}.tar.gz"
    log "installing otelcol-contrib ${version} (linux/${deb_arch})"

    download "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/${tag}/${asset}" "${tmpdir}/${asset}"
    verify_from_sha256_url "${tmpdir}/${asset}" \
        "https://github.com/open-telemetry/opentelemetry-collector-releases/releases/download/${tag}/${asset}.sha256"

    tar -xzf "${tmpdir}/${asset}" -C "${tmpdir}" otelcol-contrib
    install -m 0755 "${tmpdir}/otelcol-contrib" "${INSTALL_DIR}/otelcol-contrib"

    mkdir -p "$(dirname "${config}")"
    cat > "${config}" <<'CONFIG'
receivers:
  otlp:
    protocols:
      grpc:
        endpoint: localhost:4317
      http:
        endpoint: localhost:4318

processors:
  batch:

exporters:
  azuremonitor:
    connection_string: "${env:APPLICATIONINSIGHTS_CONNECTION_STRING}"

service:
  pipelines:
    traces:
      receivers: [otlp]
      processors: [batch]
      exporters: [azuremonitor]
    metrics:
      receivers: [otlp]
      processors: [batch]
      exporters: [azuremonitor]
    logs:
      receivers: [otlp]
      processors: [batch]
      exporters: [azuremonitor]
CONFIG
    chmod 0644 "${config}"
}

# --- superfile --------------------------------------------------------------
install_superfile() {
    local tag version asset spf_bin
    tag="$(resolve_latest_tag yorukot/superfile)"
    version="${tag#v}"
    asset="superfile-linux-v${version}-${deb_arch}.tar.gz"
    log "installing superfile ${version} (linux/${deb_arch})"

    download "https://github.com/yorukot/superfile/releases/download/${tag}/${asset}" "${tmpdir}/${asset}"
    warn_unverified "${asset}" "yorukot/superfile publishes no checksums file with its releases"

    mkdir -p "${tmpdir}/spf"
    # The archive carries POSIX extended headers that GNU tar warns about noisily.
    tar --warning=no-unknown-keyword -xzf "${tmpdir}/${asset}" -C "${tmpdir}/spf"
    spf_bin="$(find "${tmpdir}/spf" -type f -name spf -perm -u+x | head -n1)"
    [ -n "${spf_bin}" ] || die "no 'spf' binary in ${asset}"
    install -m 0755 "${spf_bin}" "${INSTALL_DIR}/spf"
    ln -sf "${INSTALL_DIR}/spf" "${INSTALL_DIR}/superfile"

    # Without this, superfile runs on its built-in defaults: the metadata plugin
    # off and its own previewer - so the exiftool and bat this image installs for
    # exactly that purpose would go unused. Unconditional here because both are
    # always present, unlike in the Feature, which had to probe for them.
    local config_dir="${TARGET_HOME}/.config/superfile"
    mkdir -p "${config_dir}"
    cat > "${config_dir}/config.toml" <<'CONFIG'
# Generated by the base-sandbox image build. Partial on purpose: superfile
# layers this over its built-in defaults, so anything left out keeps upstream's.

#-- exiftool is installed (libimage-exiftool-perl), so the metadata plugin works.
metadata = true

#-- bat is installed and symlinked to /usr/local/bin/bat.
code_previewer = "bat"
CONFIG
    chmod 0644 "${config_dir}/config.toml"
}

# --- herdr ------------------------------------------------------------------
# The terminal multiplexer coding agents run in. Binary only - nothing starts
# at container start; run 'herdr' to open or reattach to a session.
install_herdr() {
    local manifest version target expected
    manifest="${tmpdir}/herdr-manifest.json"
    target="linux-$(arch_for uname)"
    download "https://raw.githubusercontent.com/herdrdev/herdr/master/distribution/latest.json" "${manifest}"
    version="$(jq -r '.version' "${manifest}")"
    [ -n "${version}" ] && [ "${version}" != "null" ] || die "could not read the herdr version from its release manifest."
    log "installing herdr ${version} (${target})"

    download "https://github.com/herdrdev/herdr/releases/download/v${version}/herdr-${target}" "${tmpdir}/herdr"
    expected="$(jq -r --arg t "${target}" '.sha256[$t] // empty' "${manifest}")"
    if [ -n "${expected}" ]; then
        verify_sha256 "${tmpdir}/herdr" "${expected}"
    else
        warn "the herdr manifest publishes no SHA-256 for ${target} - installed UNVERIFIED."
    fi
    install -m 0755 "${tmpdir}/herdr" "${INSTALL_DIR}/herdr"

    # A partial config layered over herdr's built-in defaults: it only carries
    # the keys this image manages, so every future upstream default still applies.
    local config_dir="${TARGET_HOME}/.config/herdr"
    mkdir -p "${config_dir}"
    cat > "${config_dir}/config.toml" <<'CONFIG'
##############################################################################
# Generated by the base-sandbox image build.
#
# Intentionally PARTIAL: herdr loads its built-in defaults first and applies
# this file on top, so anything not listed here keeps upstream's default.
# Print the full commented default config with: herdr --default-config
##############################################################################

#-- Skip the first-run notification setup: a dev container is rebuilt from
#-- scratch, so the wizard would greet the user on every rebuild.
onboarding = false

[update]
#-- herdr is installed by the image build, not by herdr's own installer, so
#-- both background calls to herdr.dev are noise here.
version_check = false
manifest_check = false
CONFIG
    chmod 0644 "${config_dir}/config.toml"

    # 'herdr --skill' prints the copy bundled with THIS binary, so the skill
    # always documents the CLI that is actually installed. The skill guards
    # itself on HERDR_ENV=1, so it stays inert for an agent that was not
    # started inside a herdr pane.
    local skill_dir="${TARGET_HOME}/.claude/skills/herdr"
    if "${INSTALL_DIR}/herdr" --skill > "${tmpdir}/SKILL.md" 2>/dev/null && [ -s "${tmpdir}/SKILL.md" ]; then
        mkdir -p "${skill_dir}"
        install -m 0644 "${tmpdir}/SKILL.md" "${skill_dir}/SKILL.md"
    else
        warn "'herdr --skill' is unavailable in herdr ${version} - skipping the agent skill."
    fi

    mkdir -p /usr/share/bash-completion/completions /usr/local/share/zsh/site-functions
    if "${INSTALL_DIR}/herdr" completion bash > "${tmpdir}/herdr.bash" 2>/dev/null &&
        "${INSTALL_DIR}/herdr" completion zsh > "${tmpdir}/_herdr" 2>/dev/null &&
        [ -s "${tmpdir}/herdr.bash" ] && [ -s "${tmpdir}/_herdr" ]; then
        install -m 0644 "${tmpdir}/herdr.bash" /usr/share/bash-completion/completions/herdr
        install -m 0644 "${tmpdir}/_herdr" /usr/local/share/zsh/site-functions/_herdr
    else
        warn "'herdr completion' is unavailable in herdr ${version} - skipping shell completions."
    fi
}

install_github_cli
install_otelcol
install_superfile
install_herdr

# Execute every binary once, here, where a failure still fails the build. The
# alternative is finding out in CI, after the image has been pushed.
for bin in gh otelcol-contrib spf herdr; do
    "${INSTALL_DIR}/${bin}" --version > /dev/null || die "${bin} was installed but does not run - wrong architecture or a bad download?"
done

# Everything written under the user's home above was written as root.
chown -R "${TARGET_USER}:${TARGET_GROUP}" "${TARGET_HOME}/.config" "${TARGET_HOME}/.claude" 2>/dev/null || true
log "CLI tools installed"
