# Build notes — XZ Backdoor Labs

## 2026-06-13 — initial implementation of both labs

Built the full project per `docs/BUILD-INSTRUCTIONS.md`: `common/` helpers, Lab 1
(static inspection), Lab 2 (guided detonation), and the `docs/` walkthroughs.

### Decisions (per spec §6)

- **Backend:** Multipass primary (user's choice); Docker kept as the offline
  alternative for Lab 1 (`--network none`). Lab 2 targets Multipass only.
- **Lab 2 automation:** guided — `run.sh` confirms before going offline and before
  firing; `--auto` runs unattended.
- **Vendoring:** xzbot is fetched at runtime and **pinned** to commit
  `8ae5b706fb2c6040a91b233ea6ce39f9f09441d5`, then verified. The clean
  `build-to-host.m4` reference is **vendored** (pinned gnulib serial 3) for a
  deterministic, offline diff.
- **IOC hashes:** committed statically in `common/ioc-hashes.txt` with provenance.

### IOC hashes — how they were obtained

`build-to-host.m4` is **not** in xz's git repo (it comes from gnulib), so the Lab 1
diff uses a pinned pre-attack gnulib copy, not a git checkout — an intentional
deviation from the spec's "git clone" wording, documented in
`lab1-inspect/reference/PROVENANCE.md`.

Tarball/so hashes were computed from primary artifacts:
- `xz-5.6.0.tar.gz 0f5c81f1…` — computed from the Wayback-archived GitHub release
  asset and **corroborated** against the CERT-EU 2024-032 / ReversingLabs advisories.
- `xz-5.6.1.tar.gz 2398f4a8…`, `xz-5.6.1.tar.xz f3347773…` — computed from the
  Wayback-archived release assets (same mechanism that produced the corroborated
  5.6.0 value).
- `liblzma.so.5.6.1 605861f8…` — the IOC cited by xzbot's README and the Neo23x0
  YARA rule; Lab 2 verifies the snapshot.debian.org download against it.

### Verified ✅

- All 11 shell scripts are **shellcheck-clean** (`shellcheck -x`, v0.10.0) and pass
  `bash -n`. `patch_key.py` passes `py_compile`; `keygen.go` is `gofmt`-clean.
- **Lab 1 inspection logic ran end-to-end on the host** (read-only) against the real,
  hash-verified `xz-5.6.1.tar.gz`: the gnulib-vs-tarball diff isolates the injection,
  the 9 malicious-token flags fire, the fixtures show the `####Hello####` marker, and
  the magic-marker grep pinpoints `tests/files/bad-3-corrupt_lzma2.xz`.
- **Hash fail-safe verified:** a tampered tarball makes `verify_against_iocs` abort
  with exit 3; the cached-copy re-verify path passes.
- `make help` / `make setup` work; preflight correctly fails-safe when Multipass is
  absent. Fixed a pre-existing `make help` regex bug (digits in target names).

### Assumed / NOT yet executed ⚠️

- **No sandbox backend is installed** (Multipass/Docker absent; install needs sudo).
  So neither lab has been run *inside a guest* yet.
- **Lab 2 has not been detonated.** By design it only runs in the isolated, offline
  guest, which doesn't exist until Multipass is installed. The xzbot build, the
  liblzma key-patch, the offline-guard pass, the container arm, and the
  wire-vs-host capture are implemented and statically checked but **unproven at
  runtime**. Treat the first `make lab2` as a live bring-up.
- The `keygen` Go module fetches `cloudflare/circl` at setup time; the seed→pubkey
  derivation is assumed to match xzbot's `-seed` (both use circl `NewKeyFromSeed`),
  but this equivalence is **untested end-to-end** without a run.

## 2026-06-14 — Lab 2 reworked: isolated three-VM network, no Docker (VERIFIED)

Replaced the single-VM Docker detonation with an **isolated three-VM Multipass
network** per request: `analyst` (jumpbox + ed448 key + xzbot), `compromised`
(native sshd backdoored with liblzma keyed to the analyst), `normal` (stock sshd).
Operated from the analyst over a dedicated bridge `xzbr0` (10.77.0.0/24, no NAT).

New files: `config.sh`, `setup.sh`, `teardown.sh`, `provision/provision-{common,
analyst,compromised,normal}.sh`, `analyst/demo-{latency,capture,trigger}.sh`.
Removed: `guest/` (Dockerfile/entrypoint), `run.sh`, `setup-vuln.sh`, `trigger.sh`,
`capture.sh`. Kept `keygen/` + `patch_key.py`. Makefile `lab2`/`clean` rewired.

### Verified ✅ (ran the full lab on Multipass)

- `multipass --network name=xzbr0,mode=manual` attaches a 2nd NIC; static IPs via
  netplan; VMs reach each other on the isolated bridge with no internet.
- setup.sh stood up all three VMs, IOC-verified the liblzma, patched in the
  analyst's key (offset 0x24470), installed it as the **system** liblzma.so.5, and
  the backdoor loaded into the native sshd (no Docker, no --init/seccomp needed).
- **demo-trigger:** root RCE on compromised (`/tmp/pwned` = uid=0(root), host
  `compromised`); the SAME trigger against `normal` does nothing (stock liblzma).
- **demo-latency:** compromised ~259 ms vs normal ~143 ms avg (≈1.8×) — the
  per-connection slowdown that first exposed the backdoor.
- **demo-capture:** three pcaps on the isolated NIC; the trigger is a conspicuously
  short, aborted, cert-bearing session vs a full login.

### Fixes found during the rework

- `provision-normal.sh` `A || B && C` precedence; `local x=…y=$x` ordering;
  `sudo tee <file` → `sudo cp`; pwntools already gone (patch_key.py is dep-free).
- `demo-capture.sh`: `sudo tcpdump &` + manual `sudo kill`/`wait` HUNG (killing the
  sudo parent never reaps the tcpdump child). Rewrote with a self-terminating
  `sudo timeout 5 tcpdump`. Also made the per-scenario summary errexit/pipefail-safe.
- Reframed the pcap takeaway honestly: the trigger is distinguished by being a
  short aborted session (fewer packets), not by dwarfing a login in total bytes.

## 2026-06-13 — both labs RUN and VERIFIED on Multipass

Installed Multipass and ran both labs end-to-end in disposable guests.

### Lab 1 — verified ✅ (ran in-guest)

`make lab1` launched a VM, fetched+IOC-verified the tarball, ran `inspect.sh` in
the guest, pulled the report, and auto-purged the VM. The gnulib-vs-tarball diff,
the 9 malicious-token flags, the fixture verdicts, and the magic-marker grep all
fired in the guest.

### Lab 2 — verified ✅ (real root RCE observed)

Drove the detonation to a **confirmed pre-auth root RCE**: `/tmp/pwned` =
`uid=0(root) gid=0(root) groups=0(root)`, sshd logged only a *failed* publickey
(no `Accepted`), and the pcap was pure ciphertext. Getting there surfaced several
bugs that only appear at runtime — all now fixed in the scripts:

1. **Makefile `BACKEND` had trailing spaces** before an inline comment (Make keeps
   them), so `make lab2` saw `"multipass   "` and aborted. Fixed + scripts now trim.
2. **Multipass snap can't read host `/tmp`** — the lab-push tarball must be staged
   under `$HOME` (`.cache/`), not `mktemp`'s `/tmp`.
3. **`python3-pwntools` is not an apt package on Ubuntu 22.04** — that one missing
   package aborted the whole `apt-get`. Eliminated pwntools entirely: `patch_key.py`
   now hardcodes the fixed replacement stub (assembled+verified with binutils;
   byte-identical to xzbot's), needing only stock `python3`.
4. **Self-copy bug**: `setup-vuln.sh` did `cp "$SO" "$WORK/liblzma.so.5.6.1"` where
   `$SO` already was that path. Removed.
5. **Offline firewall severed Multipass control**: `iptables -P INPUT/OUTPUT DROP`
   killed the host↔guest management link. Now we only drop the **default route**
   (kills internet, keeps the local bridge + loopback) — which is the spec's wording.
6. **xzbot built *after* going offline** would fail (cold module cache). Now
   **pre-built during the online setup phase**; `trigger.sh` reuses the binary.
7. **The backdoor stayed dormant** until two OpenSSH-9.x defaults were undone, found
   by tracing `sshd -ddd`:
   - OpenSSH 9.x disables legacy `ssh-rsa`/`CASignatureAlgorithms=ssh-rsa`, so the
     cert was rejected *before* the hooked `RSA_public_decrypt` ran. Re-enabled.
   - The session negotiated an **ECDSA** host key, but the backdoor binds its
     trigger signature to the **RSA** host key. Forcing an **RSA-only host key**
     made xzbot and the backdoor agree. → backdoor fires.
   - Container runs with `--init` (sshd not PID 1) and `--security-opt
     seccomp=unconfined`; host exposure stays loopback-only via `-p 127.0.0.1:2222`.

### To actually run

1. `sudo snap install multipass` (and optionally `sudo apt-get install -y shellcheck`).
2. `make lab1` — safe, static; good first confidence check (try `BACKEND=docker` too).
3. `make lab2` — guided detonation; read each confirmation prompt.
4. `make clean` — purge the guest and wipe keys/pcaps.
