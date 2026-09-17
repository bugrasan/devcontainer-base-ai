# Tests

Two suites with two different jobs.

## `unit/` — host side, no image needed

Runs anywhere `bats` and `node` are available. This is where the logic that is
easy to get subtly wrong lives: the retention rule that decides what gets
deleted from the registry, and the JSONC configs that fail at apply time rather
than at commit time.

```bash
npm install -g bats @devcontainers/cli jsonc-parser
bats test/unit
```

| File | Covers |
|---|---|
| `select-prunable-versions.bats` | "current plus two past versions" against a fixed version list — which versions are deleted, which are protected, that `keep=0` is refused, that digests survive being passed newline-separated the way the caller builds them, and that the tag format the workflow publishes is still recognised as a release |
| `templates.bats` | every `devcontainer.json` parses as JSONC; each template renders with its option defaults; the sandbox template really does drop capabilities, clear the host handles, and never mount a private key |

`render-template.sh` and `parse-jsonc.js` are helpers, not tests. Three
`templates.bats` cases shell out to `devcontainer read-configuration`, which
needs a running Docker daemon and skips without one; the JSONC case always runs.

## `container/` — inside the built image

Run by
[publish-base-sandbox-image.yml](../.github/workflows/publish-base-sandbox-image.yml)
after the image is published, on both architectures, under exactly the
restrictions the template applies — so they prove the image works **when
sandboxed**, not merely when unconfined.

```bash
IMAGE=ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox:latest
docker run --rm --cap-drop=ALL --security-opt=no-new-privileges \
  --entrypoint bash -v "${PWD}/test/container:/test:ro" "${IMAGE}" /test/smoke.sh
docker run --rm --cap-drop=ALL --security-opt=no-new-privileges \
  --entrypoint bash -v "${PWD}/test/container:/test:ro" "${IMAGE}" /test/sshd.sh
```

`--entrypoint bash` is not optional: both suites assert the image ships no SSH
host keys, and the image entrypoint's whole job is to create them. The
entrypoint has its own test in the workflow.

They are mounted rather than baked in, so test code never ships in the image.

| File | Covers |
|---|---|
| `smoke.sh` | every tool resolves and answers its version flag **successfully**; no `sudo`, no `pi-dev`, no setuid or setgid binaries; the system tool directories are not writable; no baked host keys; the agent LSP config; telemetry defaults; the OTLP connection string still a runtime placeholder; the shell hardening in each bash shape |
| `sshd.sh` | host keys generated on first start, sshd running as `vscode`, a real public-key login, a second run changing nothing, and `START_SSHD=false` taking the no-start path without touching keys or the running sshd |
