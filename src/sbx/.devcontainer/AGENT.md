# Rules for agents in this sandbox

You run in a container with no network of your own.
These rules are enforced by the container setup, not by this file; this file explains them.

## Read-only paths

| Path | Why it is read-only |
|---|---|
| `.devcontainer/` | Holds your sandbox policy (allowlist, compose files, this file); you must not change your own policy |
| `.git/` | Host tools run git hooks and git config, for example `core.fsmonitor` or `credential.helper`; a change there would run code outside the sandbox |
| `.copilot/` | Holds agent configuration that host tools read |

Consequences:

- You cannot commit, branch, stash, or fetch; `git status`, `git diff`, and `git log` work
- Leave your changes uncommitted; the user reviews and commits them on the host
- Do not try to work around a read-only path, for example by copying the repository elsewhere and pointing tools at it

## Network

- You reach the internet only through the proxy at `http://127.0.0.1:3128`; the proxy variables are already set
- The proxy allows only the hostnames in `.devcontainer/squid.conf` and only HTTPS on port 443
- A blocked request returns HTTP 403 from the proxy, or `CONNECT tunnel failed, response 403`
- There is no DNS inside the container; name lookups happen in the proxy

## When you need a blocked host

1. Stop the task step that needs it
2. Tell the user the exact hostname, the port, and why the task needs it
3. Wait; the user decides, edits `squid.conf` on the host, and restarts the proxy

## Other limits

- You run without Linux capabilities and without `sudo`
- `.vscode/` and `.envrc` are writable, but the user reviews them before running host tools; do not change them unless asked
