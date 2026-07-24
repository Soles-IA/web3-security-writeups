# Pump Science (Code4rena, January 2025) — shadow audit

Solana bonding-curve protocol (x·y=k) with automated migration to a Meteora
pool. Anchor, 2030 lines of Rust across 25 programs. $20K prize pool.

Audited blind against the closed contest, then compared with the published
report (2 High, 3 Medium, judged by Koolex).

Result: identified **M-01** independently. Missed both Highs. Reached the
neighbourhood of M-03 and L-02 without closing them. One strong vector on
`create_bonding_curve` that does not appear in the report and that I could not
verify — stated as such below.

## Found

### [Medium] Last buy charges fee on the full input → matched M-01

`swap` computes the fee before the curve applies the trade:

```rust
fee_lamports = bonding_curve.calculate_fee(exact_in_amount, clock.slot)?;
buy_amount_applied = exact_in_amount - fee_lamports;
let buy_result = bonding_curve.apply_buy(buy_amount_applied)?;
```

On the final buy, `apply_buy` clamps `token_amount` to `real_token_reserves` and
recomputes `sol_amount` against a hardcoded `virtual_sol_reserves` of
115_005_359_056. The buyer therefore pays fee on SOL that never entered the
trade. In the mature phase that is 1%; during the early phase the fee is 99%, so
the mismatch is large. Confirmed by the sponsor; found by seven wardens.

## Analyzed, unresolved

### Arbitrary CPI in `create_bonding_curve`

`CreateBondingCurve` declares `system_program`, `associated_token_program`,
`token_metadata_program` and `rent` as `UncheckedAccount` — caller-supplied
addresses with no type constraint. The same protocol types them correctly in
`Swap` (`Program<'info, System>`, `Program<'info, Token>`,
`Program<'info, AssociatedToken>`), which suggests oversight rather than design.

`intialize_meta` then CPIs into the caller-supplied `token_metadata_program`,
signed with the bonding curve PDA seeds. At that point in `handler` the PDA is
still mint authority — `revoke_mint_authority()` runs afterwards. Signer
privileges propagate through CPI, and `CreateMetadataAccountsV3` hands the callee
`mint`, `mint_authority`, plus attacker-chosen `system_program` and `rent` slots,
so the SPL Token program can be passed in disguised. `BondingCurve::invariant`
compares the *curve's* token account against `real_token_reserves`, so supply
minted elsewhere leaves it untouched.

**Status: not verified.** No PoC was built (the project pins Anchor 0.29 and the
dependency graph would not resolve against my toolchain). The vector does not
appear anywhere in the official report — not as High, Medium or Low. That is not
proof of invalidity, since C4 only publishes confirmed findings, but with eight
wardens filing issues as minor as URI validation, the absence suggests something
cuts the chain that I did not find. Recorded as an open question rather than a
finding.

Precondition either way: `global.whitelist_enabled` defaults to `true`, so the
attacker must be a whitelisted creator (settable to `false` via `set_params`).

## Missed

- **[H-01]** `lock_pool` DoS: the `lockEscrow` PDA derives from pool + owner and
  its creation needs no owner signature, so anyone can create it first and make
  `create_lock_escrow` fail permanently. In `lock_pool.rs`.
- **[H-02]** `migration_token_allocation` is present in `GlobalSettingsInput` and
  never written in `Global::update_settings`. In `global.rs`.
- **[M-02]** The invariant compares `sol_escrow.lamports()` (rent included)
  against `real_sol_reserves` (rent excluded), so it passes when it should fail.
- **[M-03]** The Phase 2 fee formula yields 8.76% at slot 250 and drops to 1% at
  251 — a 7.76-point discontinuity from uncalibrated coefficients.
- **[L-02]** Integer division by 100_000 before the fee multiplication loses
  precision.
- **[L-10]** `remove_wl` is an empty function returning `Ok(())`.

## Lessons

1. **Coverage beats depth.** Both Highs live in `lock_pool.rs` and `global.rs` —
   files I never opened. I chose to go deep on `create_bonding_curve` instead of
   sweeping the whole scope first. In a fixed-window contest, a shallow pass over
   everything precedes a deep pass over anything.
2. **A recurring blind spot, now named.** H-02 is a field that arrives as a
   parameter and never reaches state. That is the same class as `contribute()`
   not writing `contribution.amount` in Rust Fund, and F-03 in StakeFlow
   (`deposit_yield` not updating `total_staked`). Third time; first time I missed
   it. Mechanical check: count fields in, count fields written, compare.
3. **A decimal formula converted to integers deserves boundary evaluation.** I
   read `calculate_fee`, noted it was decimal-math-in-integers, and moved on.
   M-03 and L-02 both live in those four lines.
4. **Without execution, the best vector stays an open question.** The arbitrary
   CPI is well-reasoned and unverified, which is worth strictly less than a
   confirmed Medium.
