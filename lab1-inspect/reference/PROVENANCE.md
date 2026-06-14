# Reference: pristine `build-to-host.upstream.m4`

`build-to-host.upstream.m4` is the **clean, pre-backdoor** version of the gnulib
macro that the xz attacker weaponized. Lab 1 diffs the backdoored tarball's
`m4/build-to-host.m4` against this file to isolate the injection.

## Why gnulib, and why this file is the right reference

`build-to-host.m4` is **not** part of the xz git repository — it legitimately
originates in [gnulib](https://www.gnu.org/software/gnulib/) and is pulled in
during the autotools bootstrap. That is exactly why the backdoor hid here: the
file only appears in the *generated release tarball*, never in git, so anyone
comparing the tarball to the GitHub source wouldn't have a git-side copy to diff.

## Exact provenance (verified 2026-06-13)

- Source: GNU gnulib, file `m4/build-to-host.m4`
- Commit: `5b92dd0a45c8d27f13a21076b57095ea5e220870` (dated **2024-01-01**, i.e.
  *before* the Feb/Mar 2024 backdoored xz 5.6.0/5.6.1 releases)
- Fetched from: `https://git.savannah.gnu.org/cgit/gnulib.git/plain/m4/build-to-host.m4?id=5b92dd0a45c8d27f13a21076b57095ea5e220870`
- This is **"serial 3"**. The backdoored tarball fakes **"serial 30"** to look newer.
- SHA-256 of this vendored copy: `331a4432631bec49fb8a1a65b08d5ec469573fe6bf8dc0d6dfed57f1e374f085`

It is committed verbatim (no added header) so the Lab 1 diff stays minimal and
shows only the attacker's additions. It is benign FSF-licensed macro text.
