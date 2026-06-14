# XZ Backdoor Labs (CVE-2024-3094)

> Safe, hands-on labs for **understanding** the xz-utils supply-chain backdoor —
> built for defenders, students, and blue-teamers.

> [!WARNING]
> **This project handles real, in-the-wild malware** (the xz **5.6.0 / 5.6.1**
> backdoor). It is provided **strictly for defensive education and authorized
> research**. Everything runs in a disposable, isolated guest with no route to the
> internet. **Do not** run these artifacts on a machine you care about, on a network
> you don't control, or against any system you are not authorized to test.
> See [SECURITY.md](SECURITY.md).

## What's inside

| Lab | What it does | Executes the payload? |
|-----|--------------|------------------------|
| **Lab 1 — Inspect** | Launch a throwaway sandbox, get the malicious tarball in *offline*, and *see* the disguise: the git-vs-tarball `build-to-host.m4` diff, the test-fixture payloads, the magic marker. | **No** — static inspection only |
| **Lab 2 — Detonate** | Build an **isolated three-VM network** (`analyst` / `compromised` / `normal`, no Docker). From the analyst jumpbox, SSH to both hosts to compare **latency** and **pcaps**, then trigger the backdoored `sshd` on `compromised` with **your own** Ed448 key (via [xzbot](https://github.com/amlweems/xzbot)) for pre-auth root RCE — while `normal` stays immune. | Yes — isolated VMs, offline, your key |

## The backdoor in one paragraph

A two-year social-engineering campaign handed a malicious maintainer release authority
over xz-utils. The payload shipped **only in the release tarball** (not git), hidden in
test fixtures, and activated at build time on x86-64 glibc systems. At runtime it used a
glibc **IFUNC** hook on `RSA_public_decrypt` (reachable via `sshd → libsystemd →
liblzma`) to give the key-holder **pre-authentication RCE** — a command hidden in an SSH
certificate's RSA modulus, ChaCha20-encrypted and **Ed448-signed**. It is not C2 and not
a magic login. Caught by Andres Freund on 29 Mar 2024 via a ~500 ms SSH slowdown, before
it reached stable distros.

## Quick start

```bash
make setup     # install/preflight checks (Multipass or Docker, tcpdump, etc.)
make lab1      # inspection sandbox
make lab2      # build the isolated 3-VM detonation network, then: multipass shell analyst
make clean     # tear everything down, purge VMs / pcaps / generated keys
```

Prerequisites and per-lab walkthroughs live in [`docs/`](docs/).

## Safety model (non-negotiable)

- Disposable isolated guest for **every** step; nothing malicious runs on the host.
- Lab 1 never builds or executes the payload.
- Lab 2's backdoored `sshd` binds to **loopback / internal bridge only** and the lab
  **refuses to run** if the guest can reach the internet.
- Only **self-generated** Ed448 keys are ever used. The original attacker key is
  cryptographically unobtainable (Ed448, ~224-bit security) — this project never
  pretends otherwise.
- Downloaded tarballs are **SHA-256 verified** against published IOCs before use.

## Credits & references

- [amlweems/xzbot](https://github.com/amlweems/xzbot) — Ed448 key patch, trigger demo, honeypot
- [lockness-Ko/xz-vulnerable-honeypot](https://github.com/lockness-Ko/xz-vulnerable-honeypot)
- [CISA alert — CVE-2024-3094](https://www.cisa.gov/news-events/alerts/2024/03/29/reported-supply-chain-compromise-affecting-xz-utils-data-compression-library-cve-2024-3094)
- [Andres Freund's oss-security disclosure](https://www.openwall.com/lists/oss-security/2024/03/29/4)
- [rya.nc — putting a payload in a valid RSA N](https://rya.nc/xz-valid-n.html)

## License

[MIT](LICENSE).
