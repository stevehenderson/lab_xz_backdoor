# Lab 1 — Inspection sandbox (static, no execution)

**Goal:** launch a disposable guest, get the backdoored xz tarball in *offline*,
and **see the disguise** with your own eyes — without ever building or running it.

> [!IMPORTANT]
> This lab is **static inspection only**. It reads bytes (`tar`, `diff`, `file`,
> `xxd`/`od`, `grep`). It never runs `./configure`, `make`, or the payload.

## Run it

```bash
# Docker (recommended for Lab 1 — true offline via --network none):
make lab1 BACKEND=docker

# Multipass VM (default backend; treated as untrusted — see caveat):
make lab1 BACKEND=multipass
```

You can also drive the script directly:

```bash
lab1-inspect/run.sh --backend docker --version 5.6.1
```

## What each script does

| Script | Side | Role |
|--------|------|------|
| `fetch.sh` | **host** | Download `xz-5.6.1.tar.gz` from the Wayback-archived release asset, `sha256sum` it, and **abort unless it matches a known-bad IOC** in `common/ioc-hashes.txt`. Idempotent (re-verifies a cached copy). |
| `run.sh` | **host** | Orchestrate: call `fetch.sh`, pull a **clean** `m4/build-to-host.m4` from git (`v5.6.1` tag), launch the guest, run `inspect.sh`, copy the log to `reports/`. |
| `inspect.sh` | **guest** | The actual inspection (below). Self-contained; degrades gracefully if `file`/`xxd` are absent. |

## What you'll see (`inspect.sh`)

1. **The git-vs-tarball diff.** `diff` of the clean upstream `m4/build-to-host.m4`
   against the tarball's. The malicious injection appears **only in the tarball** —
   the git repo is clean. This is the heart of the attack: the release tarball ≠ the source.
2. **The disguised "test fixtures."** `file` + a hexdump of
   `tests/files/bad-3-corrupt_lzma2.xz` and `tests/files/good-large_compressed.lzma`.
   A real `.xz` starts with magic `FD 37 7A 58 5A 00` (`7zXZ`); these carry the
   compressed backdoor stages instead.
3. **The magic marker.** `grep -aErl '#{4}[[:alnum:]]{5}#{4}$'` locates the
   staged-payload file by its `####.....####` end-of-line tell.
4. **The obfuscation, displayed not run.** The real `tr`/`tail`/`xz -d` de-obfuscation
   line is printed verbatim from the tarball — and **never piped to a shell**.

## Safety notes

- **Docker backend** uses `--network none`: the container genuinely cannot reach the
  network, so even an accidental command can't phone home or fetch anything.
- **Multipass backend** has no offline switch, so its guest *can* reach the network.
  That's why Lab 1 never builds the tree — reading bytes is harmless; the guest is
  treated as untrusted and is purged at the end.
- The downloaded tarball is **gitignored** and lives under `.cache/tarballs/`.
- Teardown: `make clean` (or the VM is auto-purged unless you pass `--keep`).

See [`../docs/01-inspection.md`](../docs/01-inspection.md) for the full narrative.
