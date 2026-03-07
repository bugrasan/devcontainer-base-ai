# devcontainer-base-ai

Base devcontainer configuration for AI/ML development projects.

## Usage

### Initial Setup in a New Project

1. **Add this repo as a remote** in your project:

   ```bash
   git remote add devcontainer-upstream https://<HOST>/<USER>/devcontainer-base-ai.git
   git fetch devcontainer-upstream
   ```

2. **Copy the devcontainer configuration** to your project:

   ```bash
   git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json
   git commit -m "Add devcontainer.json from devcontainer-base-ai"
   ```

### Syncing Updates

When improvements are made to this base configuration, you can selectively sync them to your project.

#### Fetch Latest Changes

```bash
git fetch devcontainer-upstream
```

#### View Upstream Commits

See what changed in the upstream devcontainer.json:

```bash
git log devcontainer-upstream/main --oneline -- .devcontainer/devcontainer.json
```

#### View Diff Against Your Current Version

```bash
git diff HEAD...devcontainer-upstream/main -- .devcontainer/devcontainer.json
```

### Sync Strategies

Choose the approach that fits your needs:

#### Option 1: Replace with Latest Version

Overwrite your local file with the latest upstream version:

```bash
git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json
git diff --cached  # Review the changes
git commit -m "Sync devcontainer.json from devcontainer-base-ai"
```

#### Option 2: Cherry-pick Specific Commits

Apply only specific improvements:

```bash
# Find the commit you want
git log devcontainer-upstream/main --oneline -- .devcontainer/devcontainer.json

# Cherry-pick it
git cherry-pick <commit-hash>
```

If the commit touches files you don't want, use the no-commit flag:

```bash
git cherry-pick -n <commit-hash>
git reset HEAD -- <files-to-exclude>
git checkout -- <files-to-exclude>
git commit -m "Cherry-pick devcontainer improvement: <description>"
```

#### Option 3: Interactive Partial Apply

Selectively apply individual changes (hunks):

```bash
git checkout -p devcontainer-upstream/main -- .devcontainer/devcontainer.json
```

This prompts you to accept or reject each change individually.

## Alternative: Plain Docker (Debian Trixie)

An alternative image definition is available at `.devcontainer/Dockerfile.trixie`.
It installs the same Debian packages as `devcontainer.json`, creates a non-root
`vscode` user, and applies dotfiles via `chezmoi`.

### Build

```bash
docker build -f .devcontainer/Dockerfile.trixie -t trixie-dev .
```

Optional: customize user name/uid/gid at build time:

```bash
docker build \
   -f .devcontainer/Dockerfile.trixie \
   -t trixie-dev \
   --build-arg USERNAME=vscode \
   --build-arg USER_UID=1000 \
   --build-arg USER_GID=1000 \
   .
```

### Run

```bash
docker run --rm -it trixie-dev
```

Optional: mount the current project into the container:

```bash
docker run --rm -it \
   -v "$(pwd):/workspace" \
   -w /workspace \
   trixie-dev
```

## Quick Reference

| Task | Command |
|------|---------|
| Add remote (once) | `git remote add devcontainer-upstream https://<HOST>/<USER>/devcontainer-base-ai.git` |
| Fetch updates | `git fetch devcontainer-upstream` |
| View upstream commits | `git log devcontainer-upstream/main --oneline -- .devcontainer/devcontainer.json` |
| View diff | `git diff HEAD...devcontainer-upstream/main -- .devcontainer/devcontainer.json` |
| Grab latest file | `git checkout devcontainer-upstream/main -- .devcontainer/devcontainer.json` |
| Cherry-pick a commit | `git cherry-pick <hash>` |
| Interactive partial apply | `git checkout -p devcontainer-upstream/main -- .devcontainer/devcontainer.json` |

## License

MIT
