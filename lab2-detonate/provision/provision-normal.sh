#!/usr/bin/env bash
# provision/provision-normal.sh — GUEST-SIDE (normal VM).
#
# The baseline: a plain, untouched sshd. We only authorize the analyst's SSH key
# so the latency/pcap comparison can connect. No liblzma changes, no config
# tweaks — this is the "what a healthy host looks like" control.
#
# Input pushed by the host into keys/: analyst-ssh.pub
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
# shellcheck source=common/lib.sh
source "${ROOT}/../common/lib.sh"

SSHPUB_FILE="${ROOT}/keys/analyst-ssh.pub"
[[ -f "$SSHPUB_FILE" ]] || die "Missing analyst SSH pubkey at $SSHPUB_FILE"

log_step "normal: ensure stock openssh-server is present and running"
if ! have_cmd sshd && ! [[ -x /usr/sbin/sshd ]]; then
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends openssh-server
fi
sudo systemctl enable --now ssh >/dev/null 2>&1 || true

log_step "normal: authorize the analyst's SSH key for root (key-only)"
sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh
sudo cp "$SSHPUB_FILE" /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys

# Confirm liblzma here is the stock distro one (NOT backdoored) — for contrast.
log_ok "normal: liblzma in use -> $(readlink -f /usr/lib/x86_64-linux-gnu/liblzma.so.5 2>/dev/null || echo '?') (stock)"
log_ok "normal provisioned (plain sshd, no backdoor)."
