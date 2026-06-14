#!/usr/bin/env bash
# lab1-inspect/run.sh — orchestrate the static-inspection lab end to end.
#
# Host work: fetch+verify the tarball, get a CLEAN upstream copy of
# m4/build-to-host.m4 from git. Guest work: run inspect.sh in a disposable
# sandbox (docker --network none = true offline; or multipass, treated as
# untrusted). Pull the log back to reports/. Never builds or runs the payload.
#
# Usage: run.sh [--backend multipass|docker] [--vm NAME] [--version 5.6.1] [--keep]
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common/lib.sh
source "${HERE}/../common/lib.sh"

BACKEND="${BACKEND:-multipass}"
VM_NAME="${VM_NAME:-xz-lab}"
VERSION="5.6.1"
KEEP=0

# Populated by main() so the backend functions can see them.
TARBALL="" ; CLEAN_M4="" ; REPORTS=""

# --- Docker backend: true offline via --network none ------------------------
run_docker() {
  require_cmd docker "Install Docker or run with --backend multipass."
  docker info >/dev/null 2>&1 || die "Docker daemon not reachable (need group membership or sudo)."

  local img="ubuntu:22.04"
  log_step "Guest (docker, --network none): static inspection"
  log_info "Image: ${img}. The container has NO network — a true offline guarantee."

  # Container-side clean-m4 path (lab1-inspect/ is mounted at /lab).
  local clean_arg=()
  if [[ -n "$CLEAN_M4" ]]; then
    local rel="${CLEAN_M4#"${HERE}/"}"
    clean_arg=(--clean-m4 "/lab/${rel}")
  fi

  # Mount the repo's lab1 dir read-only; write only to the reports dir.
  docker run --rm --network none \
    -v "${HERE}:/lab:ro" \
    -v "$(dirname "$TARBALL"):/tarballs:ro" \
    -v "${REPORTS}:/out" \
    "$img" \
    bash /lab/inspect.sh \
      --tarball "/tarballs/$(basename "$TARBALL")" \
      "${clean_arg[@]}" \
      --out /out
  log_ok "Inspection complete. Report: ${REPORTS}/inspection.log"
}

# --- Multipass backend: disposable VM (treated as untrusted) ----------------
run_multipass() {
  require_cmd multipass "Install with: sudo snap install multipass"
  log_step "Guest (multipass VM '${VM_NAME}'): static inspection"
  log_warn "Multipass has no offline toggle; the guest can reach the network."
  log_warn "Lab 1 is static-only, so this is acceptable — we NEVER build the tree."

  if ! multipass info "$VM_NAME" >/dev/null 2>&1; then
    log_info "Launching disposable VM '${VM_NAME}'..."
    multipass launch --name "$VM_NAME" --cpus 1 --memory 1G --disk 5G 22.04
  else
    log_info "Reusing existing VM '${VM_NAME}'."
  fi

  local gdir="/home/ubuntu/lab1"
  multipass exec "$VM_NAME" -- bash -c "rm -rf '$gdir' && mkdir -p '$gdir/out'"
  multipass transfer "${HERE}/inspect.sh" "${VM_NAME}:${gdir}/inspect.sh"
  multipass transfer "$TARBALL"           "${VM_NAME}:${gdir}/$(basename "$TARBALL")"
  local clean_arg=()
  if [[ -n "$CLEAN_M4" ]]; then
    multipass transfer "$CLEAN_M4" "${VM_NAME}:${gdir}/clean-build-to-host.m4"
    clean_arg=(--clean-m4 "${gdir}/clean-build-to-host.m4")
  fi

  multipass exec "$VM_NAME" -- bash "${gdir}/inspect.sh" \
    --tarball "${gdir}/$(basename "$TARBALL")" \
    "${clean_arg[@]}" \
    --out "${gdir}/out"

  multipass transfer "${VM_NAME}:${gdir}/out/inspection.log" "${REPORTS}/inspection.log"
  log_ok "Inspection complete. Report: ${REPORTS}/inspection.log"

  if [[ "$KEEP" -eq 0 ]]; then
    log_info "Tearing down VM '${VM_NAME}' (use --keep to retain it)."
    multipass delete --purge "$VM_NAME"
  else
    log_info "Keeping VM '${VM_NAME}' (--keep). Remove later with 'make clean'."
  fi
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --backend) BACKEND="${2:?}"; shift 2 ;;
      --vm)      VM_NAME="${2:?}"; shift 2 ;;
      --version) VERSION="${2:?}"; shift 2 ;;
      --keep)    KEEP=1; shift ;;
      -h|--help) grep -E '^# ' "$0" | sed 's/^# //'; exit 0 ;;
      *) die "Unknown arg: $1" ;;
    esac
  done

  # Trim stray whitespace (e.g. a padded Make variable) before dispatch.
  BACKEND="$(printf '%s' "$BACKEND" | tr -d '[:space:]')"

  REPORTS="${REPO_ROOT}/reports/lab1-${VERSION}-$(timestamp)"
  ensure_dir "$REPORTS"

  # Host step 1: verified tarball.
  log_step "Host: fetch + hash-verify xz-${VERSION} tarball"
  TARBALL="$(bash "${HERE}/fetch.sh" --version "$VERSION" | tail -1)"
  [[ -f "$TARBALL" ]] || die "fetch.sh did not yield a tarball path."

  # Host step 2: the CLEAN reference for build-to-host.m4.
  # NOTE: this file is NOT in xz's git repo — it comes from gnulib and only
  # appears in the generated tarball (that's precisely where the backdoor hid).
  # We diff against a vendored, pinned, pre-attack gnulib copy (deterministic,
  # offline). See lab1-inspect/reference/PROVENANCE.md.
  log_step "Host: using vendored pristine gnulib build-to-host.m4 as the clean reference"
  CLEAN_M4="${HERE}/reference/build-to-host.upstream.m4"
  if [[ -f "$CLEAN_M4" ]]; then
    log_info "Clean reference: $CLEAN_M4 ($(wc -l < "$CLEAN_M4") lines, gnulib serial 3)."
  else
    log_warn "Vendored reference missing; inspect.sh will fall back to showing the tail."
    CLEAN_M4=""
  fi

  case "$BACKEND" in
    docker)    run_docker ;;
    multipass) run_multipass ;;
    *) die "Unknown BACKEND='$BACKEND' (multipass|docker)" ;;
  esac

  log_ok "Lab 1 done. Read the log above; nothing was built or executed."
}

main "$@"
