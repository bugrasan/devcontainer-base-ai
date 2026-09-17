# Hardening the `base-sandbox` dev container

## Why

A coding agent with a terminal runs whatever it decides to run. The usual
answer is to approve each command, which nobody does for long. The other answer
is to make "run anything" a safe sentence — true of the container, not of the
laptop it runs on.

A dev container does not do that by default. VS Code deliberately passes a set
of handles into the container so that things feel local: your SSH agent, your
git credentials, a socket that runs commands in the **host** VS Code process.
Every one of those is reachable by anything with a shell inside the container.

The layering below follows Daniel Demmel's write-up,
[Coding agents in secured VS Code dev containers](https://www.danieldemmel.me/blog/coding-agents-in-secured-vscode-dev-containers)
([post source](https://github.com/daaain/danieldemmel.me-next/blob/main/data/blog/coding-agents-in-secured-vscode-dev-containers.mdx)),
adapted to an image that has no `sudo` and to a template that uses a plain
`image` rather than Compose.

## Status

| Layer | What it stops | In `base-sandbox` |
|---|---|---|
| 1 — no handles back to the host | using the host's SSH/GPG agent, git credentials, browser, and the VS Code IPC socket that executes commands on the host | **enabled** |
| 2 — no privilege to take | becoming root, gaining capabilities via a setuid binary, writing outside `$HOME` and the workspace | **enabled** |
| 3 — Docker socket proxy | a mounted Docker socket, which is root on the host by another name | documented, off |
| 4 — outbound egress allowlist | exfiltration and unreviewed downloads from inside the container | documented, off |

Layers 1 and 2 cost almost nothing and are on. Layers 3 and 4 each change the
shape of the setup — 3 needs Compose, 4 needs capabilities back — so they are
written up here and can be switched on later.

---

## Layer 1 — no handles back to the host

### Environment variables

`remoteEnv` in the template clears every variable VS Code uses to hand
something of yours to the container:

| Variable | What it is a handle on |
|---|---|
| `SSH_AUTH_SOCK` | the host's SSH agent — your keys, usable without the key files |
| `GPG_AGENT_INFO` | the host's GPG agent — your signing keys |
| `BROWSER` | opens URLs on the host |
| `VSCODE_IPC_HOOK_CLI` | **executes commands in the host VS Code process** |
| `VSCODE_GIT_IPC_HANDLE` | the git extension's IPC — hands over git credentials |
| `GIT_ASKPASS`, `VSCODE_GIT_ASKPASS_MAIN`, `VSCODE_GIT_ASKPASS_NODE`, `VSCODE_GIT_ASKPASS_EXTRA_ARGS` | the credential helpers behind HTTPS git operations |
| `REMOTE_CONTAINERS_IPC`, `REMOTE_CONTAINERS_SOCKETS`, `REMOTE_CONTAINERS_DISPLAY_SOCK` | the dev-containers extension's own RPC channels |
| `WAYLAND_DISPLAY`, `DISPLAY` | GUI forwarding to the host session |

`""` empties a variable; `null` removes it. Both are used above — `null` where
nothing should see the name at all.

`remoteEnv` only covers processes the IDE starts. The image therefore repeats
the same list in `/usr/local/share/base-sandbox/harden-shell.sh`, wired up three
times because no single mechanism covers every shape of shell:

| Wiring | Covers |
|---|---|
| `/etc/profile.d/00-base-sandbox-harden.sh` | login shells, interactive or not (`su -`, `bash -lc`) |
| first line of `~/.bashrc` and `~/.zshrc` | interactive shells — placed **before** Debian's "return if not interactive" guard, which would otherwise skip it |
| `BASH_ENV=/usr/local/share/base-sandbox/harden-shell.sh` | a bare `bash -c`, which reads neither of the above and is exactly how a coding agent runs a command |
| `~/.zshenv` | non-interactive `zsh`, which reads neither its rc file nor `BASH_ENV` |

**`/bin/sh` is not covered.** On Debian that is dash, which ignores `BASH_ENV`
and reads `$ENV` only when interactive, so a bare `sh -c` — which is also how
the Dev Containers CLI runs string-form lifecycle commands — sees whatever the
environment holds. There is no rc-file mechanism for it.

That gap is survivable because this is defence in depth, not the primary
control: `remoteEnv` means the variables are usually never set in the first
place. The shell wiring exists for the case where something re-introduces one.

### Sockets

Clearing a variable does not delete the socket it pointed at. `postStartCommand`
runs `harden-runtime.sh`, which deletes them and then keeps sweeping every 30
seconds for as long as the container runs. It does not stop, because these are
not created once: some appear only after the IDE finishes attaching, and VS Code
recreates them on every window reload or reconnect — a sweep with an expiry date
would be a control with an expiry date. Set `HARDEN_SWEEP_PASSES` to a positive
number for a time-boxed sweep instead.

```
/tmp/vscode-ssh-auth-*.sock
/tmp/vscode-ipc-*.sock
/tmp/vscode-git-*.sock
/tmp/vscode-remote-containers-ipc-*.sock
/tmp/vscode-remote-containers-*.js
```

### Credentials VS Code copies in

```jsonc
"dev.containers.dockerCredentialHelper": false,   // no registry credentials
"dev.containers.copyGitConfig": false             // no host git identity or helpers
```

### SSH

Only the **public** key is mounted, read-only, and `postCreateCommand` appends
it to `authorized_keys`. The private key never enters the container and the
agent is never forwarded, so `ssh` into the container works while nothing in
the container can `ssh` out as you.

### What this costs

The `code` CLI stops working inside the container — that is the IPC socket
doing its job, and the sweep keeps it that way for the life of the container.
Git over HTTPS prompts instead of using a host helper; use a token in `.env`,
or `gh auth login`.

---

## Layer 2 — no privilege to take

### No sudo

The image never installs `sudo`, and `vscode` is in no admin group. This is the
single largest difference from the `base-ai` image, and it is deliberate:
every other control in this document assumes the user cannot simply undo it.

The image also strips every setuid and setgid bit Debian ships (`su`, `mount`,
`passwd`, `chsh`, `chfn`, `gpasswd`, `newgrp`). `no-new-privileges` would
neutralise them anyway, but that flag lives in the **template's** `runArgs` — so
without the strip, the image's own promise would depend on how someone chose to
run it. `smoke.sh` asserts none are left.

Consequences, and the way round each:

| Instead of | Use |
|---|---|
| `sudo apt-get install X` | add it to `.devcontainer/base-sandbox/Dockerfile.trixie` and rebuild |
| `sudo pip install X` | `uv tool install X` or `pipx install X` |
| `sudo npm install -g X` | `npm install -g X` — the user's npm prefix is `~/.npm-global`, already on `PATH` |
| `sudo` for a privileged port | any port above 1024; sshd already uses 2222 |

### Dropped capabilities

```jsonc
"runArgs": ["--cap-drop=ALL", "--security-opt=no-new-privileges"]
```

- `--cap-drop=ALL` — even a process that reaches uid 0 cannot `chown`, bind a
  privileged port, load a module or switch user
- `--security-opt=no-new-privileges` — a setuid binary or a file capability can
  no longer raise privileges, so dropping a setuid binary into the workspace
  gains nothing

`updateRemoteUserUID` is set to `false` for the same reason: the CLI's UID fix-up
needs a root that can `chown`, and there is none. The image's `vscode` is
1000:1000, which matches the common Linux and macOS case.

### What this costs

- `ping` and `traceroute` need `CAP_NET_RAW` and stop working. `curl`, `xh` and
  `nc` are unaffected
- `strace` and `gdb` need `CAP_SYS_PTRACE` for anything beyond your own processes
- in-container `iptables` needs `CAP_NET_ADMIN` — which is what layer 4 would
  add back

If a tool you need breaks, remove the one flag rather than both, and write down
why.

### Why sshd still works

`sshd` normally runs as root because it authenticates *other* users. Here it
only ever authenticates the account it already runs as, so it needs no
privilege: `sshd-init.sh` starts it as `vscode`, on port 2222, with its config,
host keys and PID file under `~/.ssh`. `AllowUsers` lists that one account and
`UsePAM no` keeps it away from the system auth stack.

### Host keys

The image ships none. `/etc/ssh/ssh_host_*` is removed **in the same Docker
layer** that installs `openssh-server` — deleting it in a later layer would
leave the keys readable in the lower one, and a published image's private host
key is a published private key.

`sshd-init.sh` generates an ed25519 and an RSA key on first start, into
`~/.ssh/host_keys/`. They are reused for the life of that container and are
never regenerated on restart, which would otherwise trip your `known_hosts`
check every time. A rebuild produces fresh keys, so after one:

```bash
ssh-keygen -R '[localhost]:2222'
```

---

## Layer 3 — Docker socket proxy (documented, not enabled)

Mounting `/var/run/docker.sock` into a container is equivalent to giving it
root on the host: anything that can talk to that socket can start a privileged
container with the host filesystem mounted. `base-sandbox` mounts no Docker
socket at all, so today there is nothing to proxy.

If you need Docker from inside the container, do not mount the socket. Put a
filtering proxy in front of it, which means moving the template from `image` to
`dockerComposeFile`:

```yaml
# docker-compose.yml
services:
  dev:
    image: ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox:latest
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    environment:
      DOCKER_HOST: tcp://docker-proxy:2375
    command: sleep infinity

  docker-proxy:
    image: tecnativa/docker-socket-proxy:latest
    environment:
      CONTAINERS: 1
      IMAGES: 1
      INFO: 1
      NETWORKS: 1
      VOLUMES: 1
      # The dangerous half of the API stays closed.
      POST: 0
      BUILD: 0
      COMMIT: 0
      EXEC: 0
      SWARM: 0
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
```

Then in `devcontainer.json`, replace `"image"` with:

```jsonc
"dockerComposeFile": "docker-compose.yml",
"service": "dev",
"workspaceFolder": "/workspaces/${localWorkspaceFolderBasename}",
"shutdownAction": "stopCompose"
```

Cost: two containers instead of one, `runArgs` no longer applies (the flags move
into the Compose file), and read-only Docker access — no `docker build`, no
`docker exec`.

## Layer 4 — outbound egress allowlist (documented, not enabled)

Layers 1 to 3 stop the container reaching *your machine*. They do nothing about
the container reaching *the internet*, which is how source code leaves and how
unreviewed code arrives.

An allowlist is a start-up script that sets the default OUTPUT policy to DROP
and permits only DNS, the package registries you use, and your git host. It
needs capabilities that layer 2 removes, so both must be added back:

```jsonc
"runArgs": [
  "--cap-drop=ALL",
  "--cap-add=NET_ADMIN",
  "--cap-add=NET_RAW",
  "--security-opt=no-new-privileges"
]
```

and the firewall script has to run as root **before** the workload starts,
which in a no-sudo image means an `initializeCommand` on the host or a
privileged sidecar — not something the sandboxed user can do from inside.

Two honest caveats before anyone relies on this:

- an allowlist of hostnames is not an exfiltration control. `github.com` has to
  be open for git to work, and a repository is a writable channel
- the agent needs the package registries, so anything that can publish to one
  is also reachable

Treat it as a way to notice unexpected traffic, not as a boundary.

---

## Verifying it

The tests in `test/container/` run against the built image in CI, under the
same `--cap-drop=ALL --security-opt=no-new-privileges` the template applies:

| Test | Checks |
|---|---|
| `smoke.sh` | no `sudo`, no host keys in the image, `/usr/local/bin` not writable, every tool present, the shell hardening actually clears the variables |
| `sshd.sh` | keys generated on first start, sshd running as `vscode`, a public-key login succeeding, a second run changing nothing |

Run them by hand against a local image:

```bash
docker run --rm --cap-drop=ALL --security-opt=no-new-privileges \
  --entrypoint bash -v "${PWD}/test/container:/test:ro" \
  ghcr.io/bugrasan/devcontainer-base-ai/base-sandbox:latest /test/smoke.sh
```

`--entrypoint bash` is needed because the image entrypoint generates the host
keys, and both tests assert the image ships none.

## What is deliberately still open

Being clear about the gaps matters more than the list of controls:

- **the workspace** is a bind mount from the host and is fully writable. An
  agent can rewrite your source, including `.git/hooks`, which run on the host
  if you later run git there
- **the network** is unrestricted until layer 4 exists
- **`.env`** is passed into the container, so every secret in it is readable by
  anything running there. Put only what the container needs in it
- **`az`, `specify` and `claude`** live in the user's own `~/.local/bin` (their
  installers insist on it) and are only symlinked into `/usr/local/bin`. Unlike
  every other tool here, the sandboxed user can replace those three binaries
- **`sh -c`** does not get the shell hardening, as above
- **`chat.tools.global.autoApprove`** is on in the template. That is a
  deliberate trade: it is defensible *because* of the layers above, and should
  be turned off if you weaken them
