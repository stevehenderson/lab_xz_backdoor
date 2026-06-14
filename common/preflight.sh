#!/usr/bin/env bash
# common/preflight.sh — check dependencies and refuse obviously unsafe state.
# Invoked by `make setup` and as a dependency of lab1/lab2.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/lib.sh
source "${HERE}/lib.sh"

BACKEND="${BACKEND:-multipass}"

log_step "Preflight: checking host tooling (BACKEND=${BACKEND})"

missing=0
note_missing() { log_err "missing: $1"; missing=1; }

# --- Always-required host tools --------------------------------------------
for c in git sha256sum awk curl; do
  if have_cmd "$c"; then log_ok "found: $c"; else note_missing "$c"; fi
done

# --- Backend ----------------------------------------------------------------
case "$BACKEND" in
  multipass)
    if have_cmd multipass; then
      log_ok "found: multipass ($(multipass version 2>/dev/null | head -1 || echo '?'))"
    else
      note_missing "multipass"
    fi
    ;;
  docker)
    if have_cmd docker; then
      log_ok "found: docker"
      if docker info >/dev/null 2>&1; then
        log_ok "docker daemon reachable"
      else
        log_warn "docker installed but daemon not reachable (need group/sudo or 'systemctl start docker')"
      fi
    else
      note_missing "docker"
    fi
    ;;
  *)
    die "Unknown BACKEND='$BACKEND' (use 'multipass' or 'docker')."
    ;;
esac

# --- Capture / analysis tools (Lab 2; some optional) ------------------------
check_optional() { # name, hint
  if have_cmd "$1"; then log_ok "found: $1"; else log_warn "optional missing: $1 ($2)"; fi
}
check_optional tcpdump  "Lab 2 wire capture"
check_optional bpftrace "Lab 2 host-side trace"
check_optional strace   "Lab 2 fallback trace"
check_optional shellcheck "dev lint only"

# --- Install hints ----------------------------------------------------------
if [[ "$missing" -ne 0 ]]; then
  log ""
  log_warn "Some required tools are missing. Install hints:"
  cat >&2 <<'HINTS'

  Debian / Ubuntu:
    sudo apt-get update
    sudo apt-get install -y git coreutils gawk curl tcpdump bpftrace strace
    sudo snap install multipass            # backend (or: install Docker)

  Fedora:
    sudo dnf install -y git coreutils gawk curl tcpdump bpftrace strace
    sudo snap install multipass            # needs snapd; or use Docker

  Docker backend (alternative, cleaner offline guarantee for Lab 1):
    # Debian/Ubuntu: sudo apt-get install -y docker.io
    # Fedora:        sudo dnf install -y docker
    sudo systemctl enable --now docker
    sudo usermod -aG docker "$USER"   # then re-login

HINTS
  die "Preflight failed: install the missing tools above and re-run 'make setup'." 2
fi

# --- Light host-safety sanity ----------------------------------------------
log_step "Preflight: host-safety sanity"
if [[ "$(id -u)" -eq 0 ]]; then
  log_warn "Running as root on the HOST. These labs never need host root."
  log_warn "Run as a normal user; only the disposable guest does privileged work."
fi
log_ok "Preflight passed for BACKEND=${BACKEND}."
log_info "Next: 'make lab1' (safe, static) then 'make lab2' (guided detonation)."
