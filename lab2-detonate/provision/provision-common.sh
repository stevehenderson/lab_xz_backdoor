#!/usr/bin/env bash
# provision/provision-common.sh — GUEST-SIDE. Configure this VM's interface on
# the isolated bridge with a static IP (persisted via netplan). Runs on all three
# VMs. The primary NIC (multipass mgmt + internet for setup) is left untouched.
#
# Usage: provision-common.sh <static-ip-cidr e.g. 10.77.0.20/24>
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/lib.sh
source "${HERE}/../../common/lib.sh"

IPCIDR="${1:?usage: provision-common.sh <ip/cidr>}"

# The isolated NIC is the one WITHOUT the default route (that's the mgmt/primary).
DEFIF="$(ip route show default | awk '{print $5; exit}')"
NIC="$(ip -o link | awk -F': ' '{print $2}' | grep -vE "lo|${DEFIF}" | head -1)"
[[ -n "$NIC" ]] || die "Could not find the isolated NIC (only $DEFIF present?)."

log_step "Configuring isolated NIC ${NIC} -> ${IPCIDR} (mgmt stays on ${DEFIF})"

# Persist with a dedicated netplan file so it survives reboots; apply now.
cfg=/etc/netplan/99-xzlab-isolated.yaml
sudo tee "$cfg" >/dev/null <<YAML
network:
  version: 2
  ethernets:
    ${NIC}:
      dhcp4: false
      addresses: [${IPCIDR}]
YAML
sudo chmod 600 "$cfg"
sudo netplan apply
sleep 1
log_ok "Isolated NIC up: $(ip -br addr show "$NIC" | awk '{print $1, $3}')"
