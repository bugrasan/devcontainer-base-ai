#!/bin/bash
# Verifies the SSH host-key requirement end to end, INSIDE the container:
#   - the image ships no host keys
#   - the first run generates them
#   - sshd then accepts a public-key login as the unprivileged user, with no
#     sudo and no capabilities
#   - a second run is a no-op and keeps the same keys
#
#   docker run --rm -v "$PWD/test/container:/test:ro" IMAGE bash /test/sshd.sh
set -uo pipefail

INIT=/usr/local/share/base-sandbox/sshd-init.sh
PORT="${SSHD_PORT:-2222}"
KEYDIR="${HOME}/.ssh/host_keys"
pass=0
fail=0

ok() {
    printf '  ok   %s\n' "$1"
    pass=$((pass + 1))
}
no() {
    printf '  FAIL %s\n' "$1"
    fail=$((fail + 1))
}
check() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then ok "${label}"; else no "${label}"; fi
}
refute() {
    local label="$1"
    shift
    if "$@" > /dev/null 2>&1; then no "${label}"; else ok "${label}"; fi
}

echo "== before first start =="
refute "the image ships no /etc/ssh host keys" bash -c 'ls /etc/ssh/ssh_host_*_key'
refute "the image ships no user host keys" bash -c "ls ${KEYDIR}/*"

echo "== first start =="
"${INIT}" || no "sshd-init.sh exited non-zero"
check "ed25519 host key generated" test -f "${KEYDIR}/ssh_host_ed25519_key"
check "rsa host key generated" test -f "${KEYDIR}/ssh_host_rsa_key"
check "private host key is 0600" bash -c "[ \"\$(stat -c %a '${KEYDIR}/ssh_host_ed25519_key')\" = 600 ]"
check "generated config" test -f "${HOME}/.ssh/sshd_config"
check "config uses port ${PORT}" grep -qx "Port ${PORT}" "${HOME}/.ssh/sshd_config"
check "pid file written" test -s "${HOME}/.ssh/sshd.pid"
check "sshd runs as vscode, not root" bash -c \
    "[ \"\$(ps -o user= -p \"\$(cat '${HOME}/.ssh/sshd.pid')\" | tr -d ' ')\" = vscode ]"

# Give the listener a moment: sshd forks and binds asynchronously.
for _ in $(seq 1 20); do
    ss -ltn 2> /dev/null | grep -q ":${PORT}" && break
    sleep 0.5
done
check "listening on port ${PORT}" bash -c "ss -ltn | grep -q ':${PORT}'"

echo "== public-key login =="
client="${HOME}/.ssh/id_test_ed25519"
rm -f "${client}" "${client}.pub"
ssh-keygen -q -t ed25519 -f "${client}" -N '' -C smoke-test
cat "${client}.pub" >> "${HOME}/.ssh/authorized_keys"
chmod 600 "${HOME}/.ssh/authorized_keys"

out="$(ssh -p "${PORT}" -i "${client}" \
    -o StrictHostKeyChecking=no \
    -o UserKnownHostsFile=/dev/null \
    -o BatchMode=yes \
    -o ConnectTimeout=10 \
    vscode@127.0.0.1 'echo LOGIN_OK; id -un' 2>&1)"
if echo "${out}" | grep -q LOGIN_OK; then
    ok "public-key login succeeded"
else
    no "public-key login failed: ${out}"
fi
if echo "${out}" | grep -qx vscode; then
    ok "the session runs as vscode"
else
    no "unexpected session user: ${out}"
fi

echo "== second start is a no-op =="
before="$(sha256sum "${KEYDIR}/ssh_host_ed25519_key" | awk '{print $1}')"
pid_before="$(cat "${HOME}/.ssh/sshd.pid")"
"${INIT}" || no "the second sshd-init.sh run exited non-zero"
check "host key unchanged" bash -c \
    "[ \"\$(sha256sum '${KEYDIR}/ssh_host_ed25519_key' | awk '{print \$1}')\" = '${before}' ]"
check "no second sshd started" bash -c \
    "[ \"\$(cat '${HOME}/.ssh/sshd.pid')\" = '${pid_before}' ]"

echo "== START_SSHD=false is honoured =="
optout="$(START_SSHD=false "${INIT}" 2>&1)"
optout_status=$?
check "opt-out exits cleanly" test "${optout_status}" -eq 0
if echo "${optout}" | grep -q "not starting sshd"; then
    ok "opt-out took the no-start path"
else
    no "opt-out produced no 'not starting sshd' message: ${optout}"
fi
# It must also not have touched anything: same keys, same config, no new sshd.
check "opt-out generated no new keys" bash -c \
    "[ \"\$(sha256sum '${KEYDIR}/ssh_host_ed25519_key' | awk '{print \$1}')\" = '${before}' ]"
check "opt-out started no second sshd" bash -c \
    "[ \"\$(cat '${HOME}/.ssh/sshd.pid')\" = '${pid_before}' ]"

echo
printf '%d passed, %d failed\n' "${pass}" "${fail}"
[ "${fail}" -eq 0 ]
