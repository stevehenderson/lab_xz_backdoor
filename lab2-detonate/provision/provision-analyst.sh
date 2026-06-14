#!/usr/bin/env bash
# provision/provision-analyst.sh — GUEST-SIDE (analyst VM). ONLINE phase.
#
# The analyst is the operator's jumpbox. It:
#   - builds the xzbot trigger client (pinned) and the ed448 keygen helper
#   - generates a FRESH ed448 seed -> our public key (to be patched into the
#     compromised host's liblzma) and keeps the private key (the seed) here
#   - generates an SSH keypair for logging into compromised + normal
#   - installs the demo helper scripts
#
# Outputs (read by the host orchestrator): keys/pubkey.hex, ~/.ssh/id_ed25519.pub
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
# shellcheck source=common/lib.sh
source "${ROOT}/../common/lib.sh"

XZBOT_COMMIT="8ae5b706fb2c6040a91b233ea6ce39f9f09441d5"
WORK="${ROOT}/.work"; KEYS="${ROOT}/keys"
ensure_dir "$WORK"; ensure_dir "$KEYS"

log_step "analyst: install tooling (go, git, tcpdump)"
if ! have_cmd go || ! have_cmd git || ! have_cmd tcpdump; then
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends golang-go git tcpdump ca-certificates curl openssh-client
fi

log_step "analyst: fetch + pin + prebuild xzbot @ ${XZBOT_COMMIT:0:12}"
XZBOT="${WORK}/xzbot"
[[ -d "$XZBOT/.git" ]] || git clone --quiet https://github.com/amlweems/xzbot "$XZBOT"
git -C "$XZBOT" fetch --quiet origin "$XZBOT_COMMIT" 2>/dev/null || git -C "$XZBOT" fetch --quiet --all
git -C "$XZBOT" checkout --quiet "$XZBOT_COMMIT"
[[ "$(git -C "$XZBOT" rev-parse HEAD)" == "$XZBOT_COMMIT" ]] || die "xzbot pin mismatch."
( cd "$XZBOT" && go build -o ./xzbot . )
[[ -x "$XZBOT/xzbot" ]] || die "xzbot build failed."
log_ok "xzbot client built."

log_step "analyst: generate FRESH ed448 key (private stays here; public -> compromised)"
if [[ -f "${KEYS}/seed.txt" ]]; then
  SEED="$(cat "${KEYS}/seed.txt")"
else
  SEED="$(od -An -N8 -tu8 /dev/urandom | tr -d ' \n')"
fi
printf '%s\n' "$SEED" > "${KEYS}/seed.txt"; chmod 600 "${KEYS}/seed.txt"
(
  cd "${ROOT}/keygen"
  [[ -f go.mod ]] || go mod init keygen 2>/dev/null || true
  go get github.com/cloudflare/circl/sign/ed448 >/dev/null 2>&1 || true
)
PUBKEY="$(cd "${ROOT}/keygen" && go run . -seed "$SEED")"
[[ "${#PUBKEY}" -eq 114 ]] || die "bad ed448 pubkey length ${#PUBKEY}."
printf '%s\n' "$PUBKEY" > "${KEYS}/pubkey.hex"
log_ok "ed448 seed=${SEED}  pub=${PUBKEY:0:24}..."

log_step "analyst: SSH keypair for reaching compromised + normal"
if [[ ! -f "${HOME}/.ssh/id_ed25519" ]]; then
  mkdir -p "${HOME}/.ssh"; chmod 700 "${HOME}/.ssh"
  ssh-keygen -t ed25519 -N '' -f "${HOME}/.ssh/id_ed25519" -C "analyst@xzlab" >/dev/null
fi
# Don't prompt on first connect to the lab hosts (isolated net, throwaway VMs).
cat > "${HOME}/.ssh/config" <<'SSHCFG'
Host 10.77.0.*
  User root
  StrictHostKeyChecking accept-new
  UserKnownHostsFile ~/.ssh/known_hosts_xzlab
  ConnectTimeout 10
  # Offer ssh-rsa too so the comparison is apples-to-apples against both hosts.
  PubkeyAcceptedAlgorithms +ssh-ed25519
SSHCFG
chmod 600 "${HOME}/.ssh/config"

log_step "analyst: install demo helper scripts into ~/demo"
mkdir -p "${HOME}/demo"
cp "${ROOT}/analyst/"*.sh "${HOME}/demo/"
chmod +x "${HOME}/demo/"*.sh
# Drop a convenience env file the helpers source.
cat > "${HOME}/demo/lab.env" <<ENV
COMPROMISED_IP=10.77.0.20
NORMAL_IP=10.77.0.30
SEED=${SEED}
XZBOT=${XZBOT}/xzbot
ENV
log_ok "analyst provisioned. Demo helpers in ~/demo (latency, capture, trigger)."
