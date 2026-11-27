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

Shortcut: `./pm-comp.sh build|up [--build]|ps|down|proxy-restart` (or `./pm-comp`) runs steps 4, 5, and 8, a build-only run, and the proxy restart of "Change the allowlist"; `up` builds only when you pass `--build` (see `./pm-comp.sh --help`).

## Change the allowlist (`squid.conf`)

The proxy mounts `squid.conf` read-only, so edit the file on the host; no rebuild is needed.

1. Edit `squid.conf` in this folder.
2. Check the file with a temporary container; a non-zero exit means a broken file (use `podman run --http-proxy=false` for Podman):
   ```bash
   docker run --rm --user 13:13 --cap-drop=ALL --security-opt=no-new-privileges \
     -v "$PWD/squid.conf":/c.conf:ro localhost/squid:1 squid -k parse -f /c.conf
   ```
3. Restart only the proxy (Squid is not PID 1 here, so `kill -HUP 1` does not reload it):
   ```bash
   docker compose restart egress-proxy
   ```
   Podman: `./pm-comp.sh proxy-restart` runs steps 2 and 3 in one go.
   Egress stops for a moment; the agent container keeps running.
4. Check the new rule, for example with `tests/acceptance.sh`.

## Troubleshooting

- `set WS to the absolute workspace path`: `WS` is missing in `.env`.
  A relative `WS` would be read as a named volume, not your folder.
- Files in the workspace have the wrong owner: check `AGENT_UID` (Docker) or the Podman override.
- A site is blocked (403): add its hostname to `squid.conf` as described in "Change the allowlist".
