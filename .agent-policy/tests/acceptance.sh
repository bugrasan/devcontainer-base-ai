#!/usr/bin/env bash
# Acceptance tests of the handover (section 12) that run against a started CFG-01-compose project.
# Covers AT-01 to AT-06, AT-09, AT-10, AT-16, and AT-20; run from any folder:
#   .agent-policy/tests/acceptance.sh [-f override.yaml]...
# Set COMPOSE to the compose command if it is not `docker compose`.
set -uo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
read -ra compose <<< "${COMPOSE:-docker compose}"
files=(-f "$dir/cfg-01-compose.yaml")
while getopts f: o; do
  case $o in f) files+=(-f "$OPTARG") ;; *) exit 2 ;; esac
done
dc() { "${compose[@]}" "${files[@]}" "$@"; }
agent() { dc exec -T agent "$@"; }

fail=0
check() { # name, expected, actual
  if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1: expected '$2', got '$3'"; fail=1; fi
}
c() { agent curl -s -o /dev/null -w '%{http_code}/%{http_connect}' --connect-timeout 6 --max-time 15 "$@"; }

ip=$(getent hosts api.github.com | awk '{print $1; exit}')

check AT-01 200 "$(c https://api.github.com | cut -d/ -f2)"
check AT-02 403 "$(c https://example.com | cut -d/ -f2)"
check AT-03 403/000 "$(c http://github.com:22/)"
check AT-04 403 "$(c https://github.com:22/ | cut -d/ -f2)"
check AT-05 403 "$(c https://192.168.1.69/ | cut -d/ -f2)"
check AT-06 000/000 "$(c --noproxy '*' --resolve "api.github.com:443:$ip" https://api.github.com)"

out=$(agent bash -c 'ip addr add 127.0.0.2/8 dev lo 2>&1; grep -E "CapEff|NoNewPrivs" /proc/self/status')
case $out in *"Operation not permitted"*) r=denied ;; *) r="allowed: $out" ;; esac
check AT-09-ip denied "$r"
check AT-09-cap 0000000000000000 "$(grep CapEff <<< "$out" | awk '{print $2}')"
check AT-09-nnp 1 "$(grep NoNewPrivs <<< "$out" | awk '{print $2}')"

env_out=$(agent env)
for v in HTTPS_PROXY https_proxy HTTP_PROXY http_proxy; do
  check "AT-10-$v" "http://127.0.0.1:3128" "$(grep "^$v=" <<< "$env_out" | cut -d= -f2-)"
done
for v in NO_PROXY no_proxy; do
  check "AT-10-$v" "localhost,127.0.0.1,::1" "$(grep "^$v=" <<< "$env_out" | cut -d= -f2-)"
done
check AT-10-all "" "$(grep -E '^(ALL_PROXY|all_proxy|FTP_PROXY|ftp_proxy)=.+' <<< "$env_out")"
check AT-10-node 1 "$(grep '^NODE_USE_ENV_PROXY=' <<< "$env_out" | cut -d= -f2)"

logs=$(dc logs egress-proxy 2>&1)
check AT-16-tunnel yes "$(grep -q 'TCP_TUNNEL/200' <<< "$logs" && echo yes || echo no)"
check AT-16-denied yes "$(grep -q 'TCP_DENIED/403' <<< "$logs" && echo yes || echo no)"

# AT-20: the file must exist with the agent's UID in the container; compare the host owner by hand
f=.acceptance-$$
agent bash -c "id -u; touch /workspace/$f"
echo "AT-20: inspect \$WS/$f on the host; it should belong to you (Podman keep-id) or to AGENT_UID (Docker); then delete it"

exit $fail
