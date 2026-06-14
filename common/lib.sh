# shellcheck shell=bash
# common/lib.sh — shared helpers for the XZ Backdoor Labs.
#
# Source this from any lab script:
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/common/lib.sh"
#
# Provides: logging, dependency checks, SHA-256 IOC verification, an
# internet-egress isolation guard, and a y/N confirm prompt. Pure helpers —
# sourcing this file performs no side effects and exits nothing on its own.

# Resolve the repo root regardless of where the caller lives.
# common/ is always one level below the root.
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${LIB_DIR}/.." && pwd)"
export REPO_ROOT
IOC_FILE="${IOC_FILE:-${REPO_ROOT}/common/ioc-hashes.txt}"

# --- Colour-aware logging ---------------------------------------------------
# Honour NO_COLOR and non-TTY output.
if [[ -t 2 && -z "${NO_COLOR:-}" ]]; then
  _C_RESET=$'\033[0m'; _C_BLUE=$'\033[34m'; _C_GREEN=$'\033[32m'
  _C_YELLOW=$'\033[33m'; _C_RED=$'\033[31m'; _C_BOLD=$'\033[1m'
else
  _C_RESET=''; _C_BLUE=''; _C_GREEN=''; _C_YELLOW=''; _C_RED=''; _C_BOLD=''
fi

log()      { printf '%s\n' "$*" >&2; }
log_step() { printf '%s>> %s%s\n' "${_C_BOLD}${_C_BLUE}" "$*" "${_C_RESET}" >&2; }
log_info() { printf '%s[*]%s %s\n' "${_C_BLUE}" "${_C_RESET}" "$*" >&2; }
log_ok()   { printf '%s[+]%s %s\n' "${_C_GREEN}" "${_C_RESET}" "$*" >&2; }
log_warn() { printf '%s[!]%s %s\n' "${_C_YELLOW}" "${_C_RESET}" "$*" >&2; }
log_err()  { printf '%s[x]%s %s\n' "${_C_RED}" "${_C_RESET}" "$*" >&2; }

# die MESSAGE [EXIT_CODE]
die() {
  local msg="$1" code="${2:-1}"
  log_err "$msg"
  exit "$code"
}

# --- Dependency checks ------------------------------------------------------
# require_cmd CMD [HINT]  — abort if CMD is missing.
require_cmd() {
  local cmd="$1" hint="${2:-}"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    if [[ -n "$hint" ]]; then
      die "Required command '$cmd' not found. $hint"
    fi
    die "Required command '$cmd' not found."
  fi
}

# have_cmd CMD — true if CMD exists (no abort). For optional tooling.
have_cmd() { command -v "$1" >/dev/null 2>&1; }

# --- SHA-256 IOC verification ----------------------------------------------
# sha256_of FILE — print the bare 64-hex digest.
sha256_of() {
  local f="$1"
  [[ -f "$f" ]] || die "sha256_of: no such file: $f"
  sha256sum -- "$f" | awk '{print $1}'
}

# ioc_hash_for FILENAME — print the expected hash for a basename from the IOC
# file, or empty string if the filename is not listed.
ioc_hash_for() {
  local name="$1"
  [[ -f "$IOC_FILE" ]] || die "IOC file not found: $IOC_FILE"
  awk -v want="$name" '
    /^[[:space:]]*#/ { next }
    NF >= 2 && $2 == want { print $1; found=1; exit }
    END { if (!found) exit 0 }
  ' "$IOC_FILE"
}

# verify_against_iocs FILE — abort unless FILE's SHA-256 matches the IOC entry
# for its basename. This is the trust gate: a mismatch is fatal and the file is
# NOT to be used. Returns 0 on a confirmed known-bad match.
verify_against_iocs() {
  local file="$1"
  local name expected actual
  name="$(basename -- "$file")"
  expected="$(ioc_hash_for "$name")"

  if [[ -z "$expected" ]]; then
    die "No IOC hash on record for '$name' (in $IOC_FILE).
     Refusing to trust an unrecognised file. If this is a legitimate new IOC,
     add it to common/ioc-hashes.txt from a trusted advisory first."
  fi

  actual="$(sha256_of "$file")"
  if [[ "$actual" != "$expected" ]]; then
    log_err "SHA-256 MISMATCH for $name — refusing to proceed."
    log_err "  expected (known-bad IOC): $expected"
    log_err "  actual   (your download): $actual"
    die "Hash verification failed. The file is not the expected artifact. Aborting." 3
  fi
  log_ok "Verified $name matches known-bad IOC ($expected)."
}

# --- Isolation guard --------------------------------------------------------
# assert_no_host_internet — best-effort check that the HOST detonation path is
# not what we expect to be online. Mostly used as a sanity log on the host.
# The real guard runs inside the guest (see guest_assert_offline_cmd).
host_has_internet() {
  # Try a couple of cheap reachability probes without depending on DNS only.
  if have_cmd curl; then
    curl -fsS --max-time 4 -o /dev/null https://1.1.1.1 2>/dev/null && return 0
  fi
  if have_cmd ping; then
    ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && return 0
  fi
  return 1
}

# guest_assert_offline_cmd — emit a shell snippet to run INSIDE the guest that
# aborts if the guest can reach the internet. Used by Lab 2 before detonation.
# Keep this self-contained: it is injected into the guest as a string.
guest_assert_offline_cmd() {
  cat <<'GUARD'
set -euo pipefail
echo "[*] Isolation guard: asserting guest has NO route to the internet..."
reachable=0
if command -v curl >/dev/null 2>&1; then
  if curl -fsS --max-time 4 -o /dev/null https://1.1.1.1 2>/dev/null; then reachable=1; fi
fi
if [ "$reachable" -eq 0 ] && command -v ping >/dev/null 2>&1; then
  if ping -c1 -W2 1.1.1.1 >/dev/null 2>&1; then reachable=1; fi
fi
# Also treat a default route as suspicious for a detonation guest.
if ip route 2>/dev/null | grep -q '^default'; then
  echo "[!] Guest has a default route: $(ip route | grep '^default' | head -1)"
  has_default=1
else
  has_default=0
fi
if [ "$reachable" -eq 1 ]; then
  echo "[x] ABORT: guest can reach the internet (1.1.1.1 responded)." >&2
  echo "[x] A detonation guest MUST be offline. Refusing to arm the backdoor." >&2
  exit 4
fi
if [ "$has_default" -eq 1 ]; then
  echo "[!] WARNING: no internet reached, but a default route exists." >&2
  echo "[!] Detach the NIC / use an internal-only bridge for a clean run." >&2
fi
echo "[+] Isolation guard passed: guest is offline."
GUARD
}

# --- Interaction ------------------------------------------------------------
# confirm PROMPT — return 0 only if the user types 'yes'. Refuses by default.
confirm() {
  local prompt="${1:-Proceed?}" ans
  printf '%s%s [type yes to continue]%s ' "${_C_YELLOW}" "$prompt" "${_C_RESET}" >&2
  read -r ans || true
  [[ "$ans" == "yes" ]]
}

# --- Misc -------------------------------------------------------------------
# ensure_dir DIR — mkdir -p with a log line (idempotent).
ensure_dir() {
  local d="$1"
  [[ -d "$d" ]] || { mkdir -p -- "$d"; log_info "Created $d"; }
}

# timestamp — UTC stamp for filenames/reports.
timestamp() { date -u +%Y%m%dT%H%M%SZ; }
