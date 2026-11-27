# Architecture decisions – sandbox (sbx)

Decisions for the `sbx` template (`src/sbx/`) and its images.
Handover IDs (DEC, HRD, AT, OPEN, S) refer to `handover-secure-container-env.md`, the source spec of phase 1.

## AD-01 – Policy in the project, read-only for the agent

- Decision: the sandbox files (compose, `squid.conf`, Dockerfiles, scripts) live in the project's `.devcontainer/` folder; compose mounts that folder read-only over the agent's workspace
- Why: the policy is tracked in git next to the project it protects, and the template can ship it
- Departs from: handover 0.4 and S-06, which keep the policy outside the workspace
- Consequence: the agent can read its policy but not change it; AT-25 now checks that `.devcontainer/` is read-only instead of checking that no policy file appears in the workspace
- Remaining risk: a policy change can still arrive through a commit; review changes to `.devcontainer/` before you merge them

## AD-02 – `initializeCommand` runs `sbx-init.sh` on the host

- Decision: `devcontainer.json` runs `sbx-init.sh` as `initializeCommand`; `pm-comp.sh` runs it too
- Why: the agent sees the project at `/workspaces/<project folder>`, as VS Code does, but compose cannot read the folder name; the script writes it to `PROJECT=` in `.devcontainer/.env`
- The script creates `.env` from `.env.example` on the first run, then updates only the `PROJECT=` line, so user edits stay
- Departs from: DEC-02, which allows `devcontainer.json` to start and stop compose only
- Limits: the command runs on the host with the user's rights; it is a POSIX `sh` script for Linux and macOS only

## AD-03 – `.git/` and `.copilot/` read-only; no commits from the agent

- Decision: compose mounts `.git/` and `.copilot/` read-only over the workspace
- Why: host tools run `.git/hooks/` and settings in `.git/config` such as `core.fsmonitor` or `credential.helper` (HRD-13); `.copilot/` holds agent configuration that host tools read
- Consequence: the agent cannot commit, branch, stash, or fetch; the user commits on the host after review
- Missing folders: `create_host_path: false` makes compose fail instead of creating root-owned folders; `sbx-init.sh` creates empty placeholders first
- Not covered: git worktrees and submodules (`.git` is a file that points outside the workspace); `.vscode/` and `.envrc`, which stay writable and need review (AT-25)

## AD-04 – Published images, `:latest`, pull when missing

- Decision: compose references `ghcr.io/bugrasan/devcontainer-base-ai/sbx-agent:latest` and `sbx-proxy:latest` with `pull_policy: missing`, and keeps `build:` pointing at the Dockerfiles in `.devcontainer/`
- Why: users start without a local build; `up --build` still builds from the Dockerfiles, which users can adjust
- Limit: `:latest` is not reproducible; pin versions once releases are reproducible (todo)

## AD-05 – Base images pinned by digest

- Decision: `Dockerfile.agent` and `Dockerfile.proxy` pin their `FROM` images by the digest of the multi-arch index
- Why: a rebuild uses the reviewed base, not whatever the tag points at that day
- Cost: base updates need a digest bump; the weekly rebuild still refreshes the Debian packages the Dockerfiles install

## AD-06 – Separate namespaces for templates and images

- Decision: `publish-templates.yml` publishes all templates under `ghcr.io/bugrasan/devcontainer-base-ai/templates/<id>`; images stay under `ghcr.io/bugrasan/devcontainer-base-ai/<name>`
- Why: the template `sbx` and the images `sbx-agent`, `sbx-proxy`, and a possible base image `sbx` can share short names without a clash; the official devcontainers project separates templates and images the same way
- Consequence: the `base-ai` template moves to `.../templates/base-ai`; the old package `.../base-ai` gets no more updates, so the release notes must say so

## AD-07 – Image CI tests on Docker only

- Decision: `publish-sbx-images.yml` builds both images per architecture, runs `tests/acceptance.sh` on Docker, and pushes only the tested images
- Why: Podman 6 is not on the GitHub runners; Podman 6 is tested locally
- Todo: add a Podman 6 test job once it is available on the runners
