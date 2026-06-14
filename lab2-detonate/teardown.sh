#!/usr/bin/env bash
# lab2-detonate/teardown.sh — destroy the three VMs and wipe local secrets.
# Optionally remove the isolated bridge. Safe to run repeatedly.
#
# Usage: teardown.sh [--remove-bridge] [--keep-local]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/lib.sh
source "${HERE}/../common/lib.sh"
# shellcheck source=lab2-detonate/config.sh
source "${HERE}/config.sh"

REMOVE_BRIDGE=0; PURGE_LOCAL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --remove-bridge) REMOVE_BRIDGE=1; shift ;;
    --keep-local)    PURGE_LOCAL=0; shift ;;
    -h|--help) grep -E '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

log_step "Destroying VMs (purges the live malware with the compromised VM)"
if have_cmd multipass; then
  for vm in "$ANALYST_VM" "$COMPROMISED_VM" "$NORMAL_VM"; do
    multipass delete --purge "$vm" >/dev/null 2>&1 || true
    log_ok "purged ${vm} (or already gone)"
  done
  multipass purge >/dev/null 2>&1 || true
else
  log_warn "multipass not found; nothing to purge."
fi

if [[ "$REMOVE_BRIDGE" -eq 1 ]]; then
  log_step "Removing isolated bridge ${BRIDGE} (needs sudo)"
  sudo ip link set "$BRIDGE" down 2>/dev/null || true
  sudo ip link del "$BRIDGE" 2>/dev/null || true
  log_ok "bridge ${BRIDGE} removed."
else
  log_info "Left bridge ${BRIDGE} in place (use --remove-bridge to delete it)."
fi

if [[ "$PURGE_LOCAL" -eq 1 ]]; then
  log_step "Wiping host-side keys + cached lab artifacts"
  rm -rf "${REPO_ROOT}/keys" 2>/dev/null || true
  rm -f "${REPO_ROOT}/.cache/analyst-pubkey.hex" "${REPO_ROOT}/.cache/analyst-ssh.pub" \
        "${REPO_ROOT}/.cache/lab2-push.tgz" 2>/dev/null || true
  log_ok "local secrets removed."
fi
log_ok "Teardown complete."
