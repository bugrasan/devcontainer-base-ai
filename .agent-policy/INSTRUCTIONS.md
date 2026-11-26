# Run the agent sandbox: step by step

Run all commands from this folder (`.agent-policy/`), as your normal user, never with `sudo`.
Keep this folder outside the workspace you mount.

## Docker

1. Create `.env`:
   ```bash
   cp .env.example .env
   ```
2. Edit `.env`:
   - `P`: project name, for example `agent-a`
   - `WS`: absolute path of your project workspace
   - `AGENT_UID`, `AGENT_GID`: output of `id -u` and `id -g`
3. Build and start:
   ```bash
   docker compose up -d --build
   ```
4. Check that all services run (`socket-owner` exits with code 0):
   ```bash
   docker compose ps -a
   ```
5. Run the acceptance tests; expect only `PASS` lines:
   ```bash
   tests/acceptance.sh
   ```
6. Start an agent session:
   ```bash
   docker compose exec agent claude
   ```
   Open a shell in the proxy (read-only root, runs as UID 13):
   ```bash
   docker compose exec egress-proxy bash
   ```
7. Read the proxy log:
   ```bash
   docker compose logs egress-proxy
   ```
8. Stop and remove everything, including the socket volume:
   ```bash
   docker compose down -v
   ```

## Podman (rootless)

1. Install `docker-compose` and enable Podman's API socket:
   ```bash
   systemctl --user start podman.socket
   export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/podman/podman.sock
   ```
2. Stop Podman from copying host proxy variables into containers.
   Add to `~/.config/containers/containers.conf`:
   ```toml
   [containers]
   http_proxy = false
   ```
3. Create and edit `.env` as in Docker steps 1 and 2.
   `AGENT_UID` and `AGENT_GID` are not used; the override maps UID 1000 to your user.
4. Build and start with the Podman override:
   ```bash
   docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml up -d --build
   ```
5. Check the services:
   ```bash
   docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml ps -a
   ```
6. Run the acceptance tests:
   ```bash
   COMPOSE=docker-compose tests/acceptance.sh -f cfg-01-compose-podman.yaml
   ```
7. Start an agent session:
   ```bash
   docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml exec agent claude
   ```
   Open a shell in the proxy (read-only root, runs as UID 13; needs `DOCKER_HOST` from step 1):
   ```bash
   docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml exec egress-proxy bash
   ```
8. Stop and remove everything:
   ```bash
   docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml down -v
   ```

Shortcut: `./pm-comp build|up|ps|down` runs steps 4, 5, and 8 and a build-only run (see `./pm-comp --help`).

## Troubleshooting

- `set WS to the absolute workspace path`: `WS` is missing in `.env`.
- Files in the workspace have the wrong owner: check `AGENT_UID` (Docker) or the Podman override.
- A site is blocked (403): add its hostname to `squid.conf`, then `docker compose restart egress-proxy`.
