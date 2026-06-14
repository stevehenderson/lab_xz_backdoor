// keygen.go — derive the ed448 public key for a given integer seed, using the
// SAME library xzbot uses (cloudflare/circl ed448). This lets Lab 2 patch a
// FRESH, self-generated key into the backdoored liblzma instead of xzbot's
// published seed=0 demo key — satisfying the "only ever use your own key" rule.
//
// The matching PRIVATE key never leaves this machine: it is re-derived from the
// same seed by `xzbot -seed <SEED>` at trigger time. The attacker's real key is
// cryptographically unobtainable; we are not "cracking" anything — we own this key.
//
// Usage:
//
//	go run ./keygen -seed 1234567890        # prints 57-byte ed448 pubkey as hex
//
// Build is driven by setup-vuln.sh inside the guest.
package main

import (
	"flag"
	"fmt"
	"math/big"
	"os"

	"github.com/cloudflare/circl/sign/ed448"
)

func main() {
	seedn := flag.String("seed", "0", "ed448 seed (decimal integer), must match the xzbot -seed value")
	flag.Parse()

	sb, ok := new(big.Int).SetString(*seedn, 10)
	if !ok {
		fmt.Fprintln(os.Stderr, "invalid seed integer")
		os.Exit(1)
	}
	var seed [ed448.SeedSize]byte
	sb.FillBytes(seed[:])

	priv := ed448.NewKeyFromSeed(seed[:])
	pub := priv[ed448.SeedSize:] // public key is the back half (57 bytes)

	// Print as lowercase hex with no separators — ready to splice into patch.py.
	for _, c := range pub {
		fmt.Printf("%02x", c)
	}
	fmt.Println()
}
