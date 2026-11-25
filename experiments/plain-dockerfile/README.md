# Plain Dockerfile experiment

Builds the content of the `:base` image with one Dockerfile and plain `docker build`, without the devcontainer CLI or Features.
It starts from `Dockerfile.mcr-trixie` (same MCR base, apt list, uv) and adds the Features' tools as `RUN` layers.
Purpose: compare its size with the Feature-based build of `.devcontainer/base/devcontainer.json`.

## Files

- `Dockerfile` - the build: same tools as the Features, lean, release downloads checked against upstream checksums
- `smoke-test.sh` - checks plus a version list for diffing two images

## Build and compare

Needs Docker and the devcontainer CLI (`npm install -g @devcontainers/cli`).
Run from the repository root, on one machine, and at about the same time: "latest" versions resolve at build time.

```bash
docker build --pull --no-cache -t base-plain experiments/plain-dockerfile
docker pull mcr.microsoft.com/devcontainers/base:trixie
devcontainer build --workspace-folder . --config .devcontainer/base/devcontainer.json --image-name base-features --no-cache
```

```bash
docker run --rm -i --network none base-plain bash -s < experiments/plain-dockerfile/smoke-test.sh > plain.txt
docker run --rm -i --network none base-features bash -s < experiments/plain-dockerfile/smoke-test.sh > features.txt
diff features.txt plain.txt
```

```bash
docker image inspect -f '{{.Size}}' base-plain base-features
docker image ls base-plain
docker image ls base-features
docker save base-plain | gzip | wc -c
docker save base-features | gzip | wc -c
```

`docker image inspect` prints the exact unpacked bytes; the `gzip` byte counts approximate the compressed size in a registry.

## Known differences

- `init: true` is metadata, not image content: run with `docker run --init` (or set `"init": true` in the consuming devcontainer.json)
- No `devcontainer.metadata` label, so no Feature hooks, `remoteEnv`, or VS Code customizations
- No sshd, as in the current `devcontainer.json` (the Feature is commented out)
- pipx is not installed, and there is no `PIPX_*`: the Python tools come from `uv tool install` into `~/.local/bin`; anything that needs pipx must add it (`apt-get install pipx`) or use `uv tool`
- No Python dev packages (`python3-dev`, `python3-tk`, `python3-doc`, build libraries), so `python3-config` and `Python.h` are absent
- No otel start hook (autoStart is off anyway), no Copilot CLI auto-update flag, no `/usr/local/bin` links for `claude` and `specify` (`~/.local/bin` is on PATH)
- Python tools, claude, specify, herdr, and hc live in `~/.local/bin`; the Python tool set also has pylint
- Vendor installers (uv, nvm, claude, herdr) run via `curl | sh` over HTTPS without a pin or checksum, as in the Features: accepted risk
