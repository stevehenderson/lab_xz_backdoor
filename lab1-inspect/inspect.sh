#!/usr/bin/env bash
# lab1-inspect/inspect.sh — GUEST-SIDE static inspection. NEVER builds or runs.
#
# Runs inside the disposable guest. Given a verified backdoored tarball and a
# clean upstream copy of m4/build-to-host.m4, it *shows the disguise*:
#   1. diff: the injection exists in the TARBALL but not in git/upstream.
#   2. file + hexdump: the two "test fixtures" are not valid xz/lzma streams.
#   3. grep: locate the magic-marked payload file.
#   4. display (NOT execute) the obfuscated de-obfuscation line.
#
# Tooling used: tar, diff, file, xxd|od, grep, sed, awk, head. No compiler.
#
# Usage: inspect.sh --tarball PATH --clean-m4 PATH --out DIR
# Note: no 'pipefail' on purpose — we pipe into head/od and a closed pipe
# (SIGPIPE) on the producer must not abort this read-only inspection.
set -eu

TARBALL="" ; CLEAN_M4="" ; OUT="/tmp/lab1-out"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tarball)  TARBALL="${2:?}"; shift 2 ;;
    --clean-m4) CLEAN_M4="${2:?}"; shift 2 ;;
    --out)      OUT="${2:?}"; shift 2 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done
[[ -f "$TARBALL" ]]  || { echo "Missing --tarball" >&2; exit 1; }

mkdir -p "$OUT"
LOG="${OUT}/inspection.log"

# Mirror everything to a log while still printing to the screen.
exec > >(tee -a "$LOG") 2>&1

hr()  { printf '%s\n' "------------------------------------------------------------"; }
sec() { hr; printf '### %s\n' "$*"; hr; }

# file(1) is not guaranteed in a --network none guest; degrade gracefully.
file_type() {
  local f="$1"
  if command -v file >/dev/null 2>&1; then
    file -b "$f"
  else
    # Crude magic sniff so the lab still works without file(1).
    local magic; magic="$(od -A n -t x1 -N 6 "$f" | tr -d ' \n')"
    case "$magic" in
      fd377a585a00*) echo "xz compressed data (magic 7zXZ)" ;;
      5d0000*)       echo "lzma-ish stream (no xz magic)" ;;
      *)             echo "data (first6=${magic}; file(1) not installed)" ;;
    esac
  fi
}

# Pick a hexdumper that exists in the guest. Feed a fixed byte count in so the
# dumper terminates naturally (no SIGPIPE from a downstream 'head').
hexdump_head() {
  local f="$1" bytes="${2:-160}"
  if command -v xxd >/dev/null 2>&1; then
    head -c "$bytes" "$f" | xxd
  else
    head -c "$bytes" "$f" | od -A x -t x1z
  fi
}

echo "XZ Backdoor Lab 1 — static inspection"
echo "host: $(uname -srm)   when: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "tarball: $TARBALL"
echo "NOTE: This script only reads bytes. It never runs ./configure, make, or the payload."
echo

# --- Extract (data only) ----------------------------------------------------
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
sec "0. Extract the tarball (inert data, into a throwaway dir)"
tar -xzf "$TARBALL" -C "$WORK"
SRC="$(find "$WORK" -maxdepth 1 -mindepth 1 -type d | head -1)"
echo "Extracted to: $SRC"
echo "Top-level entries:"; find "$SRC" -maxdepth 1 -mindepth 1 -printf '%f\n' | sort | head -20

TARBALL_M4="${SRC}/m4/build-to-host.m4"

# --- 1. The pristine-vs-tarball diff ---------------------------------------
sec "1. m4/build-to-host.m4 — the injection (only in the tarball, not in git)"
echo "This file is NOT in xz's git repo; it comes from gnulib and only appears in"
echo "the generated tarball. That is exactly where the backdoor hid."
echo
if [[ -f "$TARBALL_M4" ]]; then
  echo "Tarball's m4/build-to-host.m4: $(wc -l < "$TARBALL_M4") lines (claims 'serial 30')"
  if [[ -n "$CLEAN_M4" && -f "$CLEAN_M4" ]]; then
    echo "Pristine gnulib build-to-host.m4: $(wc -l < "$CLEAN_M4") lines ('serial 3', pre-attack)"
    echo
    echo ">>> diff <pristine gnulib>  <tarball>   (lines with '+' are the injection):"
    # diff returns 1 when files differ; that's expected, don't let -e kill us.
    diff -u "$CLEAN_M4" "$TARBALL_M4" || true
  else
    echo "[!] No clean reference provided; showing the suspicious tail instead:"
    tail -n 20 "$TARBALL_M4"
  fi
  echo
  echo ">>> Drift-proof tell: macro lines that must NEVER exist in a build-time m4:"
  # These tokens are self-evidently malicious regardless of upstream drift:
  # a configure-time macro that greps for a magic marker, tr-deobfuscates, and
  # pipes the result to $SHELL. Flag them explicitly (literal regex, not expansion).
  # shellcheck disable=SC2016
  grep -nE 'gl_am_configmake|gl_path_map|####|AC_CONFIG_COMMANDS\(\[build-to-host\]|\| *\$SHELL|tr "\\\\t' \
    "$TARBALL_M4" | sed 's/^/    !! /' || echo "    (tokens not found — inspect by hand)"
else
  echo "[!] m4/build-to-host.m4 not found in tarball (unexpected for 5.6.0/5.6.1)."
fi

# --- 2. The disguised test fixtures ----------------------------------------
sec "2. The 'test fixtures' that are really the payload"
for fx in \
  "tests/files/bad-3-corrupt_lzma2.xz" \
  "tests/files/good-large_compressed.lzma" ; do
  f="${SRC}/${fx}"
  echo "--- $fx"
  if [[ -f "$f" ]]; then
    echo "size: $(stat -c%s "$f") bytes"
    echo "type:    $(file_type "$f")"
    echo "first bytes:"
    hexdump_head "$f" 128
  else
    echo "[!] not present"
  fi
  echo
done
echo "Teaching point: a genuine .xz starts with magic FD 37 7A 58 5A 00 ('7zXZ')."
echo "These 'corrupt' fixtures carry the compressed backdoor stages, not test data."

# --- 3. Locate the magic-marked payload ------------------------------------
sec "3. Find the magic marker  ####<5 alnum>####  (the staged-payload tell)"
echo "Running: grep -aErl '#{4}[[:alnum:]]{5}#{4}\$'  over the source tree"
if grep -aErl '#{4}[[:alnum:]]{5}#{4}$' "$SRC" 2>/dev/null; then
  :
else
  echo "(no file matched the end-of-line marker form; scanning loosely for ####..####)"
  grep -aErn '####[[:alnum:]]{5}####' "$SRC" 2>/dev/null | head -10 || echo "none found"
fi

# --- 4. Show (do NOT run) the obfuscated de-obfuscation line ----------------
sec "4. The obfuscation — DISPLAYED ONLY, never executed"
echo "The build injection pipes a fixture through 'tr' + 'xz -dc' to reconstruct"
echo "the next stage. Here is the real line(s) from the tarball's m4, verbatim:"
echo
if [[ -f "$TARBALL_M4" ]]; then
  grep -nE 'tr |tail -c|eval|xz -|\.xz|head -c' "$TARBALL_M4" 2>/dev/null | sed 's/^/    /' || \
    echo "    (no obvious obfuscation line matched; inspect $TARBALL_M4 by hand)"
else
  echo "    (m4 file unavailable)"
fi
echo
echo "[x] We do NOT pipe any of this to a shell. Reading != running."

sec "Done"
echo "Full log saved to: $LOG"
echo "Nothing was built or executed. Tear the guest down with 'make clean'."
