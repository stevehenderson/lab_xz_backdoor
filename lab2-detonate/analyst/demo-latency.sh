#!/usr/bin/env bash
# demo-latency.sh — RUN ON ANALYST. Compare SSH connect time to the backdoored
# host vs the normal host. The xz backdoor adds per-connection work in every
# forked sshd (the ~500 ms slowdown Andres Freund first noticed).
#
# Usage: ~/demo/demo-latency.sh [iterations]   (default 12)
# shellcheck disable=SC2153  # NORMAL_IP/COMPROMISED_IP come from lab.env at runtime
set -euo pipefail
# shellcheck source=/dev/null
source "$(dirname "$0")/lab.env"
N="${1:-12}"

ssh_once() { # ip -> prints elapsed seconds for one connect+auth+exec
  local ip="$1" start end
  start=$(date +%s.%N)
  ssh -o BatchMode=yes -o ConnectTimeout=10 "root@${ip}" true 2>/dev/null || true
  end=$(date +%s.%N)
  awk -v s="$start" -v e="$end" 'BEGIN{printf "%.3f", e-s}'
}

measure() { # ip label
  local ip="$1" label="$2" t sum=0
  printf 'Measuring %s (%s) over %d connections' "$label" "$ip" "$N" >&2
  for _ in $(seq 1 "$N"); do
    t=$(ssh_once "$ip"); sum=$(awk -v a="$sum" -v b="$t" 'BEGIN{print a+b}')
    printf '.' >&2
  done
  printf '\n' >&2
  awk -v s="$sum" -v n="$N" 'BEGIN{printf "%.1f", (s/n)*1000}'   # avg ms
}

echo "=== SSH connect-time: normal vs compromised ==="
# Warm up (first connect pays host-key acceptance / arp).
ssh -o BatchMode=yes -o ConnectTimeout=10 "root@${NORMAL_IP}" true 2>/dev/null || true
ssh -o BatchMode=yes -o ConnectTimeout=10 "root@${COMPROMISED_IP}" true 2>/dev/null || true

NORMAL_MS=$(measure "$NORMAL_IP" "normal")
COMP_MS=$(measure "$COMPROMISED_IP" "compromised")

printf '\n  normal      (%s): %s ms avg\n' "$NORMAL_IP" "$NORMAL_MS"
printf '  compromised (%s): %s ms avg\n' "$COMPROMISED_IP" "$COMP_MS"
awk -v n="$NORMAL_MS" -v c="$COMP_MS" 'BEGIN{
  d=c-n; printf "  difference          : %+.1f ms  (%.2fx)\n", d, (n>0? c/n : 0)
  if (d>50) print "  -> the backdoored host is measurably slower per connection.";
  else print "  -> difference is small on this run; re-run with more iterations to see it.";
}'
