# Tech debt

Workarounds in this repository, each with its upstream cause.

## TD-01 – `socket-owner` one-shot container

- Where: `src/sbx/.devcontainer/cfg-01-compose.yaml`, service `socket-owner`
- Workaround: a root container with only `CHOWN` runs `chown 13:13` on the `egress` volume so Squid (UID 13) can create its socket
- Upstream cause: Docker has no `:U` volume option to set the owner of a named volume; Podman has one
- Upstream issue: none linked yet
- Possible removal: a tmpfs-backed named volume with `o: uid=13,gid=13` (phase 2 todo in `src/sbx/.devcontainer/README.md`)

## TD-02 – Empty `.git/` and `.copilot/` placeholders

- Where: `src/sbx/.devcontainer/sbx-init.sh`
- Workaround: the script creates empty folders when a project has no `.git/` or `.copilot/`, so the read-only bind mounts have a source
- Upstream cause: a compose bind mount needs an existing source; with `create_host_path: true` Docker creates a root-owned folder instead
- Upstream issue: none; this is documented engine behavior
- Related decision: AD-03 in `docs/arch-decisions.md`

## TD-03 – Podman override not wired into `devcontainer.json`

- Where: `src/sbx/.devcontainer/devcontainer.json`
- Workaround: Podman users add `cfg-01-compose-podman.yaml` to `dockerComposeFile` by hand
- Upstream cause: `devcontainer.json` cannot select compose files per container engine
- Upstream issue: none linked yet
- Related decision: AD-02 in `docs/arch-decisions.md`
