# Sandbox (sbx) – Notes

- Runs the agent with no network; only the Squid sidecar reaches the hostnames in `.devcontainer/squid.conf`
- The agent sees the project at `/workspaces/<project folder>`; `.devcontainer/`, `.git/`, and `.copilot/` are read-only inside the container
- The agent cannot commit; commit on the host after you review its changes
- Hosts: Linux with Docker or rootless Podman 6; macOS with Docker
- Start, test, and change the allowlist: `.devcontainer/INSTRUCTIONS.md`
- Rules for the agent: `.devcontainer/AGENT.md`
- Design, limits, and todos: `.devcontainer/README.md`
- Do not open confidential repositories with VS Code yet: attaching may forward host credentials (see `.devcontainer/README.md`, Limits)
