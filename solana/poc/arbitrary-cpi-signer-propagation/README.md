# PoC: PDA signer propagation through arbitrary CPI

Executable proof that a PDA signature, once used to sign a CPI, propagates down
the call chain — so a program invoked with that signed authority can reuse it to
authorize actions the caller never intended (here: `mint_to`).

This is the mechanism behind the arbitrary-CPI finding in Pump Science
`create_bonding_curve` (see ../../pump-science.md): `token_metadata_program` is
`UncheckedAccount`, the CPI to it is signed by the bonding-curve PDA which is the
mint authority, and the revoke happens afterward. A malicious program passed as
`token_metadata_program` can mint arbitrary supply.

## What it proves

- `victim.rs` reproduces the vulnerable pattern in isolation: a PDA mint
  authority signs a CPI (`invoke_signed`) to an arbitrary, caller-supplied
  program, passing it the mint and the signing authority.
- `attacker.rs` is the malicious program: on receiving the CPI it issues its own
  `invoke` of SPL `mint_to`, using the propagated authority.
- `exploit.ts` wires them: creates a mint whose authority is the victim PDA,
  calls the victim pointing `metadata_program` at the attacker, and checks the
  attacker's token balance.

Result:
## Scope of the proof

Proves the core mechanic (signature propagation + reuse to mint) that static
analysis could not resolve. Does NOT run the full end-to-end attack against
Pump Science's actual binary with its complete account set (global, whitelist,
bonding curve) — this is the distilled pattern, not the exploit against the
deployed program.

## Instruction-data note

The victim CPIs into the attacker (an Anchor program), so its call data must be
the 8-byte Anchor discriminator of the target instruction (`sha256("global:pwn")[:8]`),
not a placeholder. Same for the test calling the victim.

## Run

Environment per ../../../poc-template/POC_SETUP.md (Solana release 4.1.1 /
Cargo 1.89). Build both programs with `cargo-build-sbf`, then `anchor test
--skip-build`. Watch the `before/after` balance line, not the mocha "passing"
(the test prints the verdict; it has no failing assert).
