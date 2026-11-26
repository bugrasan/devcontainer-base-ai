# Agent sandbox, phase 1

Runs a coding agent in a container with no network, next to a Squid proxy sidecar that allows only a reviewed list of hostnames.
This is phase 1 of the handover (DEC-10, CFG-01-compose): the agent container and the proxy only.
Service containers, agent sockets, CFG-01-devc, and CFG-01-gha are later steps (S-03, S-04, S-09).

| File | Purpose |
|---|---|
| `cfg-01-compose.yaml` | Compose project: `socket-owner` (one-shot), `egress-proxy`, `agent` |
| `cfg-01-compose-podman.yaml` | Override for rootless Podman: maps UID 1000 to the host user |
| `squid.conf` | Egress allowlist (CFG-00-squid); edit per project |
| `Dockerfile.agent` | `ghcr.io/bugrasan/devcontainer-base-ai/base:latest` plus `socat`, `dnsutils`, `iproute2`, `xxd`; `sudo` removed |
| `Dockerfile.proxy` | `mcr.microsoft.com/devcontainers/base:trixie` plus `squid` and `socat`; runs as UID 13 |
| `.env.example` | Variables to copy into `.env` |
| `tests/acceptance.sh` | AT-01 to AT-06, AT-09, AT-10, AT-16, AT-20 against a running project |

## Run

Keep this folder outside the workspace you mount (handover 0.4): the agent can write its workspace and would otherwise rewrite its own policy.

```bash
cd .agent-policy
cp .env.example .env    # set P, WS, and on Docker AGENT_UID and AGENT_GID
docker compose up -d --build
docker compose exec agent claude
```

Rootless Podman: run docker-compose against Podman's API socket and add the override.

```bash
systemctl --user start podman.socket
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml up -d --build
```

Set `http_proxy = false` in `containers.conf` first (HRD-05, PIT-01).

Test and tear down:

```bash
tests/acceptance.sh                                  # Docker
COMPOSE=docker-compose tests/acceptance.sh -f cfg-01-compose-podman.yaml   # Podman
docker compose down -v
```

## Status

Untested: the handover marks CFG-01-compose as untested (S-02), and this environment had no container engine.
Run AT-01 to AT-26 (handover section 12) on Docker and on Podman before relying on it.
Open points that affect this build: IPv6 (OPEN-08), agent UID without an account (OPEN-15), and the `.codeberg.org` and LAN entries in `squid.conf`, which are placeholders.
