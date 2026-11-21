# Plain Dockerfile experiment

Builds the content of the `:base` image with one Dockerfile and plain `docker build`, without the devcontainer CLI, Features, or a `mcr.microsoft.com/devcontainers` base image.
Purpose: compare its size with the Feature-based build of `.devcontainer/base/devcontainer.json`.

## Files

- `Dockerfile` – parity build on `debian:trixie`: same packages, tools, files, and image config as the Feature build, in seven `RUN` layers; embedded scripts and config files are verbatim copies of the Feature versions named in its comments
- `smoke-test.sh` – parity checks plus a version list; both images must pass, and their version lists should differ only as listed under Known differences

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

- No `devcontainer.metadata` label, so a dev container started from this image runs no Feature hooks: no sshd start through `/usr/local/share/ssh-init.sh`, no Copilot CLI update check, and no OpenTelemetry start hook
- No MCR image labels, `meta.env`, `devcontainer-info`, or common-utils marker file
- No `/tmp/dev-container-features` and no Feature VS Code customizations (extensions, settings): only the devcontainer CLI and its metadata label add them
- git (source build) and Oh My Zsh: the Feature build takes them from its MCR base image snapshot, this build fetches the newest at build time
