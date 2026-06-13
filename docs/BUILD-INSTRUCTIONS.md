# Build Instructions: XZ Backdoor (CVE-2024-3094) Hands-On Labs

> **For:** Claude Code (or any coding agent) working in a fresh GitHub repository.
> **Goal:** Turn the two labs described in my blog post ("Anatomy of a Backdoor:
> The XZ Utils Supply-Chain Attack") into a real, runnable, well-documented project.
> **Audience for the finished project:** defenders, students, and blue-teamers who
> want to *safely* see the xz backdoor's artifacts and mechanism with their own hands.

---

## 0. Read this first — scope, ethics, and hard safety rules

This project handles **real, in-the-wild malware** (the xz 5.6.0/5.6.1 backdoor). It is
strictly for **defensive education and authorized research**. The build must make the
*safe* path the *easy* path. These are non-negotiable requirements, not suggestions —
bake them into the scripts, not just the docs:

1. **Everything runs in a disposable, isolated guest** (VM or `--network none`
   container). No lab step may run the malicious payload on the host.
2. **No payload execution in Lab 1.** Lab 1 is *static inspection only*: read, diff,
   `xxd`, `grep`. Never `./configure && make` the malicious tree.
3. **Lab 2 (detonation) runs the backdoor only inside a throwaway guest on an
   internal-only / loopback network with no route to the internet.** Bind the
   vulnerable `sshd` to `127.0.0.1` or an internal bridge only.
4. **Only ever use a *self-generated* Ed448 key** for triggering (via xzbot's key
   patch). Never imply the original attacker key is obtainable — it is not.
5. **Scripts must verify before they trust:** check SHA-256 of any downloaded tarball
   against the published IOC hashes, and refuse to proceed on mismatch.
6. **Scripts must fail safe:** if they can't confirm isolation (e.g., the guest has
   internet egress when it shouldn't), they abort with a clear message.
7. **Make teardown trivial and obvious** (`make clean` / `multipass delete --purge`).
8. Add a top-level `SECURITY.md` and a prominent `README.md` warning. Add a
   `LICENSE` (MIT is fine unless I say otherwise).

If any instruction below would violate these rules, **stop and ask me** instead of
improvising.

---

## 1. Background the project must convey (don't re-research from scratch)

- **CVE-2024-3094**, CVSS 10.0. Backdoor in xz-utils **5.6.0** and **5.6.1**.
- The malicious code shipped in the **release tarball only**, not the git repo
  (modified `m4/build-to-host.m4`); the binary payload hid in test fixtures
  (`tests/files/bad-3-corrupt_lzma2.xz`, `tests/files/good-large_compressed.lzma`).
- It activated only when building on **x86-64 Linux, glibc, GCC**, under a
  deb/rpm packaging flow.
- At runtime it used a **glibc IFUNC** resolver to hook **`RSA_public_decrypt`** in
  `sshd` (reachable because `sshd` → `libsystemd` → `liblzma` on Debian/Fedora).
- The trigger is **pre-auth RCE**: a crafted cert carries a command in the RSA
  **modulus N**, ChaCha20-encrypted and **Ed448-signed**. Valid signature →
  `system(command)` as root before auth completes. Invalid → falls through to the
  real function (stealth). It is **not** C2 and **not** a magic login.
- Discovered by **Andres Freund**, disclosed to oss-security **29 Mar 2024**, after a
  ~500 ms SSH login slowdown + Valgrind errors. Caught before hitting stable distros.

Upstream tools the project should build on (do not reinvent):
- **xzbot** — `https://github.com/amlweems/xzbot` (Ed448 key patch, trigger demo,
  honeypot/logging sshd). This is the reference for Lab 2.
- **xz-vulnerable-honeypot** — `https://github.com/lockness-Ko/xz-vulnerable-honeypot`
  (a known-good way to stand up a genuinely vulnerable sshd + bpftrace/strace/tcpdump).
- Analysis references: rya.nc "valid N" writeup; Kaspersky Securelist 3-part series;
  CISA alert for IOC hashes.

---

## 2. Target repository layout

Create approximately this structure (adjust names if you have a clearly better idea,
but keep the two-lab separation):

```
.
├── README.md                  # project overview + the big safety warning
├── SECURITY.md                # responsible-use statement, reporting
├── LICENSE
├── CLAUDE.md                  # short agent guide pointing back at this spec
├── Makefile                   # top-level entrypoints: setup / lab1 / lab2 / clean
├── .gitignore                 # ignore VMs, pcaps, downloaded tarballs, keys
├── common/
│   ├── lib.sh                 # shared bash helpers (logging, hash check, isolation guard)
│   ├── ioc-hashes.txt         # known-bad SHA-256s for xz 5.6.0/5.6.1 tarballs
│   └── preflight.sh           # checks deps (multipass/docker), refuses unsafe state
├── lab1-inspect/
│   ├── README.md
│   ├── run.sh                 # orchestrates the inspection lab end-to-end
│   ├── fetch.sh               # host-side download + hash verify (never in guest)
│   └── inspect.sh             # runs inside guest: diff, xxd, file, grep magic marker
├── lab2-detonate/
│   ├── README.md
│   ├── run.sh                 # orchestrates the detonation lab
│   ├── setup-vuln.sh          # stand up vulnerable sshd + xzbot (guest only)
│   ├── trigger.sh             # build/patch own Ed448 key, fire xzbot trigger
│   ├── capture.sh             # tcpdump + host-side bpftrace/strace/journal capture
│   └── teardown.sh
└── docs/
    ├── 01-inspection.md       # narrative walkthrough mirroring the blog Lab 1
    ├── 02-detonation.md       # narrative walkthrough mirroring the blog Lab 2
    └── 03-how-it-works.md     # the mechanism + trigger sequence + "can't crack the key"
```

---

## 3. Lab 1 — Inspection sandbox (static, no execution)

**Outcome:** a one-command lab that launches a disposable guest, gets the malicious
tarball in *offline*, and lets the user *see* the disguise without ever building it.

Build:
- **`fetch.sh` (host):** download the xz 5.6.1 (and optionally 5.6.0) source tarball,
  `sha256sum` it, compare against `common/ioc-hashes.txt`, **abort on mismatch**.
- **Two sandbox backends, user picks one:**
  - **Multipass:** `multipass launch`, then `multipass transfer` the verified tarball
    in (guest needs no internet). Document that Multipass has no offline toggle, so
    the guest is treated as untrusted.
  - **Docker:** `docker run --rm --network none -v <dir>:/xz:ro ...` — the cleaner
    offline guarantee for pure static work.
- **`inspect.sh` (guest):** must demonstrate, with output captured to a log:
  1. `git clone` the clean upstream (`https://github.com/tukaani-project/xz`) **on the
     host** (or a pre-seeded copy) and `diff` its `m4/build-to-host.m4` against the
     tarball's — showing the injection exists only in the tarball.
  2. `file` + `xxd | head` on the two disguised test fixtures (show they aren't valid
     xz streams).
  3. `grep -aErl "#{4}[[:alnum:]]{5}#{4}$"` to locate the magic-marked payload file.
  4. Display (but **do not execute**) the obfuscated `tr` de-obfuscation line as a
     teaching artifact.
- **Teardown:** `multipass delete --purge` / container auto-removal.

**Acceptance criteria:**
- `make lab1` runs start-to-finish on a clean machine with only the documented deps.
- The guest never has working internet during inspection (or it's a read-only
  offline container).
- A hash mismatch hard-stops the run.
- No step builds or executes the payload; a reviewer can confirm this by reading
  `inspect.sh`.

---

## 4. Lab 2 — Detonation sandbox (controlled trigger + capture)

**Outcome:** a one-command lab that stands up a genuinely backdoored `sshd` inside an
isolated guest, triggers it with the **user's own** Ed448 key via xzbot, and captures
both the (encrypted) wire traffic and the host-side smoking gun.

Build:
- **`setup-vuln.sh`:** stand up the vulnerable environment inside the guest. Prefer
  reusing xzbot's and/or lockness-Ko's provided environment over compiling liblzma
  yourself. The vulnerable `sshd` must bind **loopback or internal bridge only**.
- **Isolation guard:** before starting the backdoored sshd, assert the guest has **no
  default route to the internet**; abort otherwise.
- **`trigger.sh`:** follow xzbot's README to patch in a **freshly generated** Ed448
  keypair, then fire a benign demonstrator command (e.g. `id > /tmp/pwned` or
  `touch /tmp/xz-demo`). Never a destructive or network-egress command.
- **`capture.sh`:** run concurrently —
  - `tcpdump -w` the session (to show it's encrypted post-kex; payload NOT in cleartext).
  - host-side `bpftrace`/`strace` on the sshd and/or `journalctl` grep for the
    `xzbot: magic` log line — the part the wire can't show.
- Produce a short generated report correlating the two (wire vs. host).
- **`teardown.sh`:** purge the VM, delete generated keys/pcaps.

**Acceptance criteria:**
- `make lab2` stands up, triggers, captures, and tears down with one command.
- The demo proves the *contrast*: the benign command executed (file appears) with **no
  successful-auth log entry**, and the pcap shows only encrypted traffic.
- Refuses to run if the guest can reach the internet.
- Uses only a self-generated key; documents clearly that the real attacker key is
  unobtainable (Ed448, ~224-bit security).

---

## 5. Cross-cutting engineering requirements

- **Bash, set `-euo pipefail`**, shellcheck-clean. Put shared logic in `common/lib.sh`.
- **Idempotent + re-runnable:** scripts detect existing state and don't duplicate it.
- **Every script prints what it's about to do and why**, especially safety checks.
- **No secrets or payloads committed.** `.gitignore` must exclude downloaded tarballs,
  generated keys, VMs, and `*.pcap`.
- **Preflight (`common/preflight.sh`)** checks for required tools (`multipass` or
  `docker`, `tcpdump`, `git`, `sha256sum`, optionally `bpftrace`/`strace`) and prints
  install hints for Debian/Ubuntu and Fedora.
- **Docs mirror the blog narrative** but are self-contained; include the three Mermaid
  diagrams from the post (source can be copied; render to PNG offline with
  `@mermaid-js/mermaid-cli` if you want images, or keep as fenced ```mermaid```).
- **Tested:** before declaring done, dry-run what you safely can (shellcheck, `--help`
  paths, hash-check logic with a deliberately wrong hash) and report what you could and
  could not execute in your environment.

---

## 6. Decisions to confirm with me before or during the build

1. **Sandbox backend priority** — is Multipass the primary path, with Docker as the
   offline alternative, or should I prioritize Vagrant/libvirt for stronger isolation?
2. **How far to automate Lab 2** — fully scripted detonation, or a guided/manual
   walkthrough with copy-paste steps (safer, more transparent)?
3. **Vendoring** — git-submodule xzbot/honeypot, or fetch them at runtime with pinned
   commit + hash?
4. **Hosting the IOC hashes** — pull from CISA/distro advisories at build time, or
   commit a static `ioc-hashes.txt` with sources cited?

Default to the *safer / more transparent* option if I'm unavailable, and note the
assumption in the README.

---

## 7. Definition of done

- [ ] `make setup` / `make lab1` / `make lab2` / `make clean` all work on a clean host.
- [ ] All safety guards implemented in code (isolation checks, hash verify, fail-safe).
- [ ] README + SECURITY.md make the risks and the safe path unmistakable.
- [ ] Lab 1 never executes the payload; Lab 2 only ever uses a self-generated key.
- [ ] docs/ walkthroughs read cleanly and match what the scripts actually do.
- [ ] shellcheck passes; nothing sensitive is committed.
- [ ] A short top-level CHANGELOG or build note records what was verified vs. assumed.
