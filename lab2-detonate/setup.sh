#!/usr/bin/env bash
# lab2-detonate/setup.sh — HOST orchestrator for the three-VM detonation lab.
#
# Builds an ISOLATED bridge network with three Multipass VMs and NO Docker:
#   analyst (jumpbox, holds the ed448 private key + xzbot)
#   compromised (native sshd backdoored with liblzma patched to ANALYST's key)
#   normal (plain sshd, the control)
#
# Setup is the only ONLINE phase. Afterwards each VM's default route is dropped
# (kills internet, keeps the Multipass mgmt link + the isolated bridge), and the
# compromised host's isolation is asserted before you drive the demo from analyst.
#
# Usage: setup.sh [--stay-online]   (--stay-online skips the offline step, for debugging)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/lib.sh
source "${HERE}/../common/lib.sh"
# shellcheck source=lab2-detonate/config.sh
source "${HERE}/config.sh"

STAY_ONLINE=0
[[ "${1:-}" == "--stay-online" ]] && STAY_ONLINE=1

require_cmd multipass "Install with: sudo snap install multipass"
KEYS_REL="lab2-detonate/keys"
CACHE="${REPO_ROOT}/.cache"; ensure_dir "$CACHE"

gx()  { multipass exec "$1" -- bash -lc "$2"; }                 # gx VM "shell line"
prov(){ multipass exec "$1" -- bash -lc "cd '${GUEST_DIR}/lab2-detonate' && $2"; }

# --- 0. isolated bridge -----------------------------------------------------
log_step "Ensuring isolated bridge ${BRIDGE} (${BRIDGE_HOST_IP}/24, no NAT)"
if ! ip link show "$BRIDGE" >/dev/null 2>&1; then
  log_info "Creating ${BRIDGE} (needs sudo)..."
  sudo ip link add name "$BRIDGE" type bridge
  sudo ip addr add "${BRIDGE_HOST_IP}/24" dev "$BRIDGE"
  sudo ip link set "$BRIDGE" up
else
  log_ok "${BRIDGE} already present."
fi
multipass networks 2>/dev/null | grep -q "$BRIDGE" \
  || die "Multipass does not see ${BRIDGE}. Create it and retry."

# --- 1. launch the three VMs ------------------------------------------------
launch_vm() { # name spec
  local name="$1" spec="$2"
  if multipass info "$name" >/dev/null 2>&1; then
    log_ok "VM '${name}' already exists."
  else
    log_info "Launching '${name}' on ${BRIDGE}..."
    # shellcheck disable=SC2086
    multipass launch --name "$name" $spec \
      --network "name=${BRIDGE},mode=manual" "$UBUNTU_RELEASE"
  fi
}
log_step "Launching VMs"
launch_vm "$ANALYST_VM" "$ANALYST_SPEC"
launch_vm "$COMPROMISED_VM" "$COMPROMISED_SPEC"
launch_vm "$NORMAL_VM" "$NORMAL_SPEC"

# --- 2. push the lab payload + configure isolated NICs ----------------------
push_lab() { # vm
  local vm="$1" tar="${CACHE}/lab2-push.tgz"
  tar -C "$REPO_ROOT" -czf "$tar" common lab2-detonate
  gx "$vm" "rm -rf '${GUEST_DIR}' && mkdir -p '${GUEST_DIR}'"
  multipass transfer "$tar" "${vm}:${GUEST_DIR}/lab.tgz"
  gx "$vm" "tar -C '${GUEST_DIR}' -xzf '${GUEST_DIR}/lab.tgz' && rm -f '${GUEST_DIR}/lab.tgz'"
  rm -f "$tar"
}
log_step "Pushing lab payload + configuring isolated NICs"
push_lab "$ANALYST_VM";     prov "$ANALYST_VM"     "bash provision/provision-common.sh ${ANALYST_IP}/24"
push_lab "$COMPROMISED_VM"; prov "$COMPROMISED_VM" "bash provision/provision-common.sh ${COMPROMISED_IP}/24"
push_lab "$NORMAL_VM";      prov "$NORMAL_VM"      "bash provision/provision-common.sh ${NORMAL_IP}/24"

# --- 3. provision analyst (generates the keys) ------------------------------
log_step "Provisioning analyst (builds xzbot, generates ed448 + SSH keys)"
prov "$ANALYST_VM" "bash provision/provision-analyst.sh"

log_step "Collecting analyst's public keys"
multipass transfer "${ANALYST_VM}:${GUEST_DIR}/${KEYS_REL}/pubkey.hex" "${CACHE}/analyst-pubkey.hex"
multipass transfer "${ANALYST_VM}:/home/ubuntu/.ssh/id_ed25519.pub"    "${CACHE}/analyst-ssh.pub"
log_ok "ed448 pub: $(cut -c1-24 "${CACHE}/analyst-pubkey.hex")...  ssh: $(awk '{print $1,$3}' "${CACHE}/analyst-ssh.pub")"

# --- 4. distribute analyst keys to the other two ----------------------------
distribute() { # vm
  local vm="$1"
  gx "$vm" "mkdir -p '${GUEST_DIR}/${KEYS_REL}'"
  multipass transfer "${CACHE}/analyst-pubkey.hex" "${vm}:${GUEST_DIR}/${KEYS_REL}/analyst-pubkey.hex"
  multipass transfer "${CACHE}/analyst-ssh.pub"    "${vm}:${GUEST_DIR}/${KEYS_REL}/analyst-ssh.pub"
}
log_step "Distributing analyst keys to normal + compromised"
distribute "$NORMAL_VM"
distribute "$COMPROMISED_VM"

# --- 5. provision normal, then compromised (arms the backdoor) --------------
log_step "Provisioning normal (plain sshd control)"
prov "$NORMAL_VM" "bash provision/provision-normal.sh"

log_step "Provisioning compromised (backdoored liblzma + sshd) — ARMS the host"
prov "$COMPROMISED_VM" "bash provision/provision-compromised.sh"

# --- 6. go offline + isolation guard ---------------------------------------
if [[ "$STAY_ONLINE" -eq 0 ]]; then
  log_step "Taking VMs offline (drop default route; keep mgmt + isolated bridge)"
  for vm in "$ANALYST_VM" "$COMPROMISED_VM" "$NORMAL_VM"; do
    gx "$vm" "sudo ip route del default 2>/dev/null || true"
  done
  log_step "Isolation guard on compromised (must have no internet)"
  guest_assert_offline_cmd | multipass exec "$COMPROMISED_VM" -- bash -s \
    || die "Isolation guard FAILED on compromised — it can still reach the internet."
else
  log_warn "--stay-online: VMs keep internet (debug only; not isolated)."
fi

# --- done -------------------------------------------------------------------
cat >&2 <<DONE

$(printf '%s' "${_C_GREEN}${_C_BOLD}")=== Lab 2 ready ===${_C_RESET:-}
  Network: ${BRIDGE} (${SUBNET}.0/24, isolated)
    analyst     ${ANALYST_IP}   (your jumpbox — control plane)
    compromised ${COMPROMISED_IP}   (backdoored sshd; liblzma keyed to analyst)
    normal      ${NORMAL_IP}   (plain sshd, control)

  Drive the demo from the analyst:
    multipass shell ${ANALYST_VM}
      ~/demo/demo-latency.sh        # SSH timing: normal vs compromised
      ~/demo/demo-capture.sh        # pcap the handshakes + the trigger
      ~/demo/demo-trigger.sh        # fire the backdoor (root RCE on compromised)

  Tear it all down:  make clean   (or bash lab2-detonate/teardown.sh)
DONE
