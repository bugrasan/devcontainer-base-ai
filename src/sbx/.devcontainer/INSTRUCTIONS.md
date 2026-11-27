# Run the sandbox: step by step

Run all commands from the project's `.devcontainer/` folder, as your normal user, never with `sudo`.
Hosts: Linux and macOS.

The containers use the published images `sbx-agent` and `sbx-proxy` by default.
Add `--build` to `up` to build them from the Dockerfiles in this folder instead.

`sbx-init.sh` prepares the host side before every start; `devcontainer.json` and `pm-comp.sh` run it for you:

- creates `.env` from `.env.example` on the first run (sets `P`, `AGENT_UID`, and `AGENT_GID`), then only updates the `PROJECT=` line
- creates empty `.git/` and `.copilot/` folders in the project root if they are missing; compose mounts them read-only

The agent sees the project at `/workspaces/<project folder>`.
The project folder name may contain only letters, digits, `.`, `_`, and `-`.

## Docker

1. Prepare the host side:
   ```bash
   ./sbx-init.sh
   ```
2. Start (pulls the images if they are missing):
   ```bash
   docker compose up -d
   ```
   Fetch newer published images: `docker compose pull`.
3. Check that all services run (`socket-owner` exits with code 0):
   ```bash
   docker compose ps -a
   ```
4. Run the acceptance tests; expect only `PASS` lines:
   ```bash
   tests/acceptance.sh
   ```
5. Start an agent session:
   ```bash
   docker compose exec agent claude
   ```
   Open a shell in the proxy (read-only root, runs as UID 13):
   ```bash
   docker compose exec egress-proxy bash
   ```
6. Read the proxy log:
   ```bash
   docker compose logs egress-proxy
   ```
7. Stop and remove everything, including the socket volume:
   ```bash
   docker compose down -v
   ```

## Podman 6 (rootless)

Linux hosts only: the steps use the user `podman.socket` from systemd.
On macOS, use Docker; the Podman route there (`podman machine`) is not tested.

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
3. Prepare the host side: `./sbx-init.sh`.
   `AGENT_UID` and `AGENT_GID` are not used; the override runs the agent as UID 1000 and maps it to your user.
4. Start with the Podman override:
   ```bash
   docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml up -d
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

Shortcut: `./pm-comp.sh build|pull|up [--build]|ps|down|proxy-restart` runs `sbx-init.sh`, steps 4, 5, and 8, a build-only run, an image update, and the proxy restart of "Change the allowlist" (see `./pm-comp.sh --help`).

## VS Code or the devcontainer CLI

Not cleared for confidential repositories yet: attaching may forward host credentials (README.md, Limits).

1. Podman only: add `"cfg-01-compose-podman.yaml"` to `dockerComposeFile` in `devcontainer.json`, and do Podman steps 1 and 2.
2. Open the project folder and run "Dev Containers: Reopen in Container", or:
   ```bash
   devcontainer up --workspace-folder ..
   ```
   `initializeCommand` runs `sbx-init.sh` on the host first.

## Change the allowlist (`squid.conf`)

The proxy mounts `squid.conf` read-only; the agent sees it read-only too.
Edit the file on the host; no rebuild is needed.

1. Edit `squid.conf` in this folder.
2. Check the file in a one-off proxy container; a non-zero exit means a broken file:
   ```bash
   docker compose run --rm --no-deps -T egress-proxy squid -k parse -f /config/squid.conf
   ```
3. Restart only the proxy (Squid is not PID 1 here, so `kill -HUP 1` does not reload it):
   ```bash
   docker compose restart egress-proxy
   ```
   Podman: `./pm-comp.sh proxy-restart` runs steps 2 and 3 in one go.
   Egress stops for a moment; the agent container keeps running.
4. Check the new rule, for example with `tests/acceptance.sh`.

## Troubleshooting

- `required variable P is missing a value` or `required variable PROJECT is missing a value`: run `./sbx-init.sh`.
- `bind source path does not exist` for `.git` or `.copilot`: run `./sbx-init.sh`; it creates the missing folders.
- Files in the workspace have the wrong owner: check `AGENT_UID` in `.env` (Docker) or the Podman override.
- A site is blocked (403): add its hostname to `squid.conf` as described in "Change the allowlist".
- git fails in the container with `not a git repository`: the project is a git worktree or submodule, which the sandbox does not support.
