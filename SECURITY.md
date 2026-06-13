# Security & Responsible Use

## Purpose

This repository exists for **defensive security education and authorized research**
into the xz-utils backdoor (CVE-2024-3094). It helps defenders understand how the
attack hid, how it activated, and why network detection alone was blind to it.

## What this repository contains

- Tooling to **inspect** the malicious xz 5.6.0 / 5.6.1 artifacts statically.
- Tooling to **detonate** the backdoor in a fully isolated, throwaway guest using a
  **self-generated** Ed448 key, for the purpose of observing and detecting it.

It does **not** contain, and will never contain:
- The original attacker's private key (it is cryptographically unobtainable).
- Any capability to attack third-party systems.
- The malicious payload committed to the repo (it is fetched and hash-verified at
  runtime, never stored here).

## Hard safety rules (enforced in code, not just docs)

1. Every lab step runs inside a disposable, isolated VM or `--network none` container.
2. Lab 1 performs **static inspection only** — it never builds or runs the payload.
3. Lab 2's backdoored `sshd` binds to loopback / an internal bridge only, and the lab
   **aborts** if the guest has a route to the internet.
4. Only self-generated Ed448 keys are used to trigger the backdoor.
5. Downloaded tarballs are SHA-256 verified against published IOCs before use; a
   mismatch hard-stops the run.
6. Teardown is one command and removes VMs, captures, and generated keys.

## Acceptable use

You may use this project only on infrastructure you own or are explicitly authorized to
test, for learning and defense. You are responsible for complying with all applicable
laws and policies. **Do not** deploy the vulnerable artifacts on production systems,
shared hosts, or any network you do not fully control.

## Reporting

Found a problem with this lab tooling (e.g., a safety guard that doesn't hold)? Open an
issue or contact the maintainer. For the underlying vulnerability itself, refer to the
[CISA advisory](https://www.cisa.gov/news-events/alerts/2024/03/29/reported-supply-chain-compromise-affecting-xz-utils-data-compression-library-cve-2024-3094)
and your distribution's security team.
