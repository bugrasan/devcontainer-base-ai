# Sandbox (sbx)

Runs a coding agent in a container with no network, next to a Squid proxy sidecar that allows only a reviewed list of hostnames.
This is phase 1 of the handover (DEC-10, CFG-01-compose): the agent container and the proxy only.
Service containers, agent sockets, and CFG-01-gha are later steps (S-03, S-04, S-09).

Step-by-step guide: `INSTRUCTIONS.md`.
Rules the agent sees: `AGENT.md`.

| File | Purpose |
|---|---|
| `cfg-01-compose.yaml` | Compose project: `socket-owner` (one-shot), `egress-proxy`, `agent` |
| `cfg-01-compose-podman.yaml` | Override for rootless Podman: maps UID 1000 to the host user |
| `devcontainer.json` | Starts and stops the compose project from VS Code or the devcontainer CLI |
| `sbx-init.sh` | Host-side preparation: `.env`, missing `.git/` and `.copilot/` folders |
| `pm-comp.sh` | Short commands for rootless Podman (`build`, `pull`, `up`, `ps`, `down`, `proxy-restart`) |
| `squid.conf` | Egress allowlist (CFG-00-squid); edit per project |
| `Dockerfile.agent` | Source of `sbx-agent`: the `base` image plus `socat`, `dnsutils`, `iproute2`, `xxd`; `sudo` removed |
| `Dockerfile.proxy` | Source of `sbx-proxy`: `mcr.microsoft.com/devcontainers/base:trixie` plus `squid` and `socat`; runs as UID 13 |
| `.env.example` | Template for `.env`, which `sbx-init.sh` creates |
| `tests/acceptance.sh` | AT-01 to AT-06, AT-09, AT-10, AT-16, AT-20, and the read-only part of AT-25 |
| `AGENT.md` | What the agent can and cannot do here, and why |

Images: `ghcr.io/bugrasan/devcontainer-base-ai/sbx-agent` and `ghcr.io/bugrasan/devcontainer-base-ai/sbx-proxy`, built from the Dockerfiles above.

## Design decisions

Full records with reasons: [docs/arch-decisions.md](https://github.com/bugrasan/devcontainer-base-ai/blob/main/docs/arch-decisions.md).

- AD-01: the policy lives in the project's `.devcontainer/` folder and is mounted read-only over the agent's workspace; departs from handover 0.4 and S-06, which keep it outside the workspace
- AD-02: `devcontainer.json` runs `sbx-init.sh` on the host as `initializeCommand`; departs from DEC-02, which allows no lifecycle commands
- AD-03: `.git/` and `.copilot/` are mounted read-only; the agent cannot commit (HRD-13)
- AD-04: compose uses the published images with `pull_policy: missing` and the `:latest` tag; `up --build` builds them from the Dockerfiles instead
- AD-05: the base images in both Dockerfiles are pinned by digest

## Limits

- VS Code attach is not cleared for confidential repositories: which host credentials it forwards is unverified (OPEN-12, AT-23)
- Whether VS Code can install its server in a container without network is unverified; the allowlist has no VS Code download hosts
- Git worktrees and submodules are not supported: their `.git` file points outside the workspace, so git fails inside the container
- `.vscode/` and `.envrc` stay writable; review them before you run VS Code tasks or direnv on the host (HRD-13, AT-25)
- VS Code with Podman: add `cfg-01-compose-podman.yaml` to `dockerComposeFile` in `devcontainer.json`
- Renaming the project folder updates `PROJECT` in `.env` but keeps the compose project name `P`

## Status

Untested end to end: the handover marks CFG-01-compose as untested (S-02).
Run AT-01 to AT-26 (handover section 12) on Docker and on Podman 6 before relying on it.
Open points that affect this build: IPv6 (OPEN-08), agent UID without an account (OPEN-15), and the `.codeberg.org` and LAN entries in `squid.conf`, which are placeholders.

## Todo

- Reproducible releases: pin the image tags in `cfg-01-compose.yaml` to versions instead of `:latest`
- Bump the digests in the Dockerfiles automatically, for example with Dependabot
- CI: run the acceptance tests on Podman 6 as well (the runners ship an older Podman)
- macOS: support Podman through `podman machine` (socket path from `podman machine inspect`); today only Docker is documented there
- Git worktree support
- Phase 2: VS Code attach (OPEN-12, AT-23) and VS Code server installation without network
- Phase 2: test the `egress` volume as a tmpfs-backed named volume (SVC-14) via `driver_opts` `type: tmpfs`, `device: tmpfs`, `o: uid=13,gid=13`
  - Goal: no stale `http.sock` after `down` without `-v`, and possibly no need for `socket-owner`
  - Check on Docker and on rootless Podman: Podman documents mount options other than `uid`/`gid` as needing root privileges, so rootless tmpfs volumes may fail (unverified)
  - Check that docker-compose passes the options through Podman's API socket (AT-26, OPEN-21)
- Phase 3: sign the images with cosign, publish provenance and an SBOM, and reference the images by digest
- Phase 3 or later (optional): hide the host username and home path that `mount` shows inside rootless Podman containers
  - Cause: the overlay mount options (`lowerdir`, `upperdir`, `workdir`) list the host's Podman storage path under `~/.local/share/containers/storage`
  - Option: set `graphroot` in `~/.config/containers/storage.conf` to a neutral path, or run the sandbox under a dedicated host user (untested)
