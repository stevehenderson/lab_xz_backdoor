#!/usr/bin/env bash
# lab1-inspect/fetch.sh — HOST-SIDE download + SHA-256 IOC verification.
#
# Downloads a backdoored xz release tarball into the repo's .cache/ and refuses
# to proceed unless its SHA-256 matches a known-bad IOC in common/ioc-hashes.txt.
# The tarball is INERT data here — Lab 1 never builds or runs it. Verification
# happens on the host so a tampered/wrong download is caught before it ever
# reaches the guest.
#
# Usage: fetch.sh [--version 5.6.1|5.6.0] [--cache DIR]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/lib.sh
source "${HERE}/../common/lib.sh"

VERSION="5.6.1"
CACHE_DIR="${REPO_ROOT}/.cache/tarballs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version) VERSION="${2:?}"; shift 2 ;;
    --cache)   CACHE_DIR="${2:?}"; shift 2 ;;
    -h|--help) grep -E '^# ' "$0" | sed 's/^# //'; exit 0 ;;
    *) die "Unknown arg: $1" ;;
  esac
done

case "$VERSION" in
  5.6.0|5.6.1) : ;;
  *) die "Only 5.6.0 or 5.6.1 are supported (these are the backdoored releases)." ;;
esac

require_cmd curl "Install curl to download the archived tarball."
require_cmd sha256sum

TARBALL="xz-${VERSION}.tar.gz"
DEST="${CACHE_DIR}/${TARBALL}"
ensure_dir "$CACHE_DIR"

log_step "Lab 1 fetch: acquiring ${TARBALL} (will hash-verify before trusting)"

# Idempotent: if a verified copy already exists, don't re-download.
if [[ -f "$DEST" ]]; then
  log_info "Found existing ${TARBALL} in cache; re-verifying..."
  if actual="$(sha256_of "$DEST")" && [[ "$actual" == "$(ioc_hash_for "$TARBALL")" ]]; then
    verify_against_iocs "$DEST"
    log_ok "Cached tarball already verified. Path: $DEST"
    printf '%s\n' "$DEST"
    exit 0
  fi
  log_warn "Cached copy failed verification; re-downloading."
  rm -f -- "$DEST"
fi

# The original GitHub release assets were pulled after disclosure. The Wayback
# Machine preserved the exact bytes; we pull from there and then hash-verify.
# Multiple candidates are tried for resilience.
declare -a URLS=(
  "https://web.archive.org/web/20240329id_/https://github.com/tukaani-project/xz/releases/download/v${VERSION}/${TARBALL}"
  "https://web.archive.org/web/2024id_/https://github.com/tukaani-project/xz/releases/download/v${VERSION}/${TARBALL}"
)

ok=0
tmp="${DEST}.part"
for url in "${URLS[@]}"; do
  log_info "Trying: ${url}"
  if curl -fsSL --max-time 120 -o "$tmp" "$url"; then
    mv -f -- "$tmp" "$DEST"
    log_ok "Downloaded $(stat -c%s "$DEST" 2>/dev/null || echo '?') bytes -> $DEST"
    ok=1
    break
  fi
  log_warn "Source failed, trying next mirror..."
done
rm -f -- "$tmp" 2>/dev/null || true
[[ "$ok" -eq 1 ]] || die "Could not download ${TARBALL} from any known archive mirror."

# THE trust gate. A mismatch is fatal — see common/lib.sh::verify_against_iocs.
verify_against_iocs "$DEST"

log_ok "Tarball ready and verified (inert — never built in Lab 1): $DEST"
# Emit the path on stdout for the orchestrator to capture.
printf '%s\n' "$DEST"
