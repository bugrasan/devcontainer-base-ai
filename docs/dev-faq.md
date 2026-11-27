# Developer FAQ

## Build and smoke-test the `:base` image locally

### With Docker (CI or a local machine)

```bash
devcontainer build --workspace-folder . \
  --config .devcontainer/base/devcontainer.json --image-name base-ai:local
docker run --rm \
  -v "$PWD/.devcontainer/base/smoke-test.sh:/tmp/smoke/smoke-test.sh:ro" \
  -v "$PWD/.devcontainer/base/lsp-check.py:/tmp/smoke/lsp-check.py:ro" \
  base-ai:local bash /tmp/smoke/smoke-test.sh
```

### Inside this dev container

This dev container runs under rootless host podman.
It has no Docker and no `CAP_SYS_ADMIN`, and `/proc` has masked paths.
The steps below were verified on 2026-11-27 with devcontainer CLI 0.91.0 and podman 5.4.2.

1. Install the tools:

   ```bash
   sudo apt-get install -y podman uidmap passt
   npm install -g @devcontainers/cli
   ```

2. Create `pod.sh`.
   Rootless podman fails because `newuidmap` cannot write `uid_map`.
   The wrapper runs podman as root in a new user namespace that maps the parent's three extents.
   Storage must be on the ext4 bind mount `/workspaces/devcontainer-base-ai.worktrees`; overlay on the container's overlay root fails.

   ```bash
   #!/bin/bash
   # Run podman as root in a user namespace mapping the parent's 3 extents.
   M="--map-users=0:0:1000 --map-users=1000:1000:1 --map-users=1001:1001:64536 --map-groups=0:0:1000 --map-groups=1000:1000:1 --map-groups=1001:1001:64536"
   exec sudo unshare -U $M --setgroups allow -m --propagation private -f \
     podman --root /workspaces/devcontainer-base-ai.worktrees/.podman/root --runroot /tmp/podrun \
     --cgroup-manager cgroupfs --events-backend file --storage-driver overlay "$@"
   ```

3. Create `pod-docker.sh`, a `docker` shim for the devcontainer CLI.
   `RUN` steps need the host pid, uts, ipc, and network namespaces, because a new proc mount and `sethostname` are denied.
   The shim adds these flags right after the `build` token and calls `pod.sh`.

   ```bash
   #!/bin/bash
   # Add host-namespace flags after "build", then call pod.sh.
   out=(); done=0
   for a in "$@"; do
     out+=("$a")
     if [ $done = 0 ] && [ "$a" = build ]; then
       out+=(--isolation=oci --pid=host --uts=host --ipc=host --network=host)
       done=1
     fi
   done
   exec /path/to/pod.sh "${out[@]}"
   ```

4. Build the image.
   A warm build takes about 5–6 minutes.
   The image is about 3.6 GB and takes about 4 GB of storage.

   ```bash
   devcontainer build --docker-path ./pod-docker.sh --workspace-folder . \
     --config .devcontainer/base/devcontainer.json \
     --image-name localhost/base-ai:local
   ```

5. Run the smoke test as a build `RUN` step.
   `podman run` fails here: crun cannot create cgroups, and `--cgroups=disabled` needs a private pid namespace, which cannot mount proc.
   Copy `smoke-test.sh` and `lsp-check.py` from `.devcontainer/base/` into a scratch folder, and add this `Containerfile`:

   ```dockerfile
   FROM localhost/base-ai:local
   COPY smoke-test.sh lsp-check.py /tmp/smoke/
   RUN bash /tmp/smoke/smoke-test.sh
   ```

   Then build it from that folder:

   ```bash
   /path/to/pod.sh build --no-cache --isolation=oci --pid=host --uts=host \
     --ipc=host --network=host -f Containerfile .
   ```

6. Clean up.
   The build writes `.devcontainer/base/devcontainer-lock.json`; don't commit it.
   Free the storage with `pod.sh system reset -f`, or delete the storage folder.

## How do I enable a deferred language server?

jdtls (Java), terraform-ls, and LemMinx (XML) are available but commented out.

1. In `.devcontainer/base/features/lsp-servers/install.sh`, uncomment the `WORK_DIR` and `trap` lines and the server's block; jdtls also needs the `apt-get` lines for `openjdk-25-jdk-headless`
2. In `.devcontainer/base/features/lsp-config/install.sh`, uncomment the server's row in `SERVERS`
3. For Java with Claude Code, add `jdtls-lsp@claude-plugins-official` to the `claude-code` Feature's `lspPlugins` in `.devcontainer/base/devcontainer.json`; the `jdtls` row covers Copilot CLI only
4. Add the binary and the server ID to the lists in `.devcontainer/base/smoke-test.sh`, and a fixture for one of its file extensions to `FIXTURES` in `.devcontainer/base/lsp-check.py`
   For jdtls, don't add `jdtls` to `LSP_SERVERS`: it expects the plugin `jdtls-lsp@base-ai-lsp`, which is never installed.
   Append `jdtls` to `COPILOT_SERVERS` and `jdtls-lsp@claude-plugins-official` to `CLAUDE_PLUGINS` instead.
5. Bump the version of each changed Feature

## How do I turn off a language server for one project?

For Copilot CLI, add `.github/lsp.json` to the project:

```json
{"lspServers": {"yaml": {"disabled": true}}}
```

A project entry with the same server name overrides or removes the server from the image.
Check the result with `copilot lsp list` in the project folder.
For Claude Code, run `claude plugin disable <id>-lsp@base-ai-lsp --scope project` in the project folder.
It writes `"enabledPlugins": {"<id>-lsp@base-ai-lsp": false}` to the project's `.claude/settings.json`.

## Why does VS Code need extensions for languages the agents already cover?

VS Code doesn't read the Claude Code or Copilot CLI plugins.
Its language features come from extensions, which bundle their own servers.
JSON, HTML, CSS, Markdown, and TypeScript are built in, and the `node` and `python` Features add ESLint and Pylance.
The template adds `redhat.vscode-yaml`, `mads-hartmann.bash-ide-vscode`, `docker.docker`, and `tamasfe.even-better-toml` for YAML, Bash, Dockerfile, and TOML.
