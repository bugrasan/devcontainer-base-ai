#!/usr/bin/env bash
# Short commands for the rootless Podman setup in INSTRUCTIONS.md (Podman section)
#
# TODO
# - Shell completion for bash and zsh: complete the commands (build, up, ps, down,
#   proxy-restart), the options (-h, --help, -v, --version), and `up --build`
set -euo pipefail

VERSION=2

usage() {
  cat <<EOF
Usage: pm-comp.sh <command> [--build]   (also callable as pm-comp)   version ${VERSION}
EOF
  cat <<'EOF'
Wraps: docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml

Commands:
  build   build the images only
  up      start the containers (up -d); builds only images that are missing
          up --build  also rebuild the images (up -d --build)
  ps      list all containers, including exited ones (ps -a)
  down    stop and remove everything, including volumes (down -v)
  proxy-restart
          check squid.conf with 'squid -k parse', then restart only egress-proxy
          (egress stops briefly; the agent keeps running)

Options:
  -h, --help      show this help
  -v, --version   show the script version

It starts Podman's user API socket and sets DOCKER_HOST to it.
It needs docker-compose and a .env file (see INSTRUCTIONS.md).
Run the script from any folder; it changes to its own folder first.
EOF
}

cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
  usage >&2
  exit 2
fi

case "$1" in
  -h|--help) usage; exit 0 ;;
  -v|--version) echo "pm-comp.sh version ${VERSION}"; exit 0 ;;
  build|up|ps|down|proxy-restart) ;;
  *) echo "pm-comp.sh: unknown command '$1'" >&2; usage >&2; exit 2 ;;
esac

# Only `up` takes an argument: --build
if [ $# -eq 2 ] && { [ "$1" != up ] || [ "$2" != --build ]; }; then
  echo "pm-comp.sh: unexpected argument '$2' for '$1'" >&2
  usage >&2
  exit 2
fi

command -v docker-compose >/dev/null || { echo "pm-comp.sh: docker-compose not found" >&2; exit 1; }
[ -f .env ] || { echo "pm-comp.sh: .env missing; copy .env.example (INSTRUCTIONS.md)" >&2; exit 1; }

# docker-compose talks to Podman through its user API socket
systemctl --user start podman.socket
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR:?XDG_RUNTIME_DIR is not set}/podman/podman.sock"

compose=(docker-compose -f cfg-01-compose.yaml -f cfg-01-compose-podman.yaml)

case "$1" in
  build) exec "${compose[@]}" build ;;
  up)
    if [ "${2:-}" = --build ]; then
      exec "${compose[@]}" up -d --build
    fi
    exec "${compose[@]}" up -d ;;
  ps)    exec "${compose[@]}" ps -a ;;
  down)  exec "${compose[@]}" down -v ;;
  proxy-restart)
    # A broken squid.conf would put the proxy in a restart loop and stop all egress
    command -v podman >/dev/null || { echo "pm-comp.sh: podman not found" >&2; exit 1; }
    podman run --rm --user 13:13 --cap-drop=ALL --security-opt=no-new-privileges \
      --network=none --http-proxy=false \
      -v "$PWD/squid.conf":/c.conf:ro "${SQUID_IMAGE:-localhost/squid:1}" \
      squid -k parse -f /c.conf || { echo "pm-comp.sh: squid.conf check failed; proxy not restarted" >&2; exit 1; }
    exec "${compose[@]}" restart egress-proxy ;;
esac
