# WOOFi Swap on Solana (Sherlock, September 2024) — shadow audit

Solana AMM using an sPMM (synthetic proactive market making) formula — the same
model whose EVM version was exploited months earlier by pushing the WOO price to
near zero. Rust/Anchor, two programs (`woofi` + `rebate_manager`), ~3100 lines.
$21.5K to the #1 auditor.

Audited blind against the closed contest, then compared with the official report
(2 High, 2 Medium). Result: **caught 2 of 4 after being pointed at the right
file; the two Highs I missed cost me the same lesson twice — coverage means the
whole scope, not the whole main file.**

## What I got right: the swap core is sound

Full coverage of the swap chain (`swap.rs`, `swap_math.rs`, `wooracle.rs`,
`woopool.rs`, `get_price.rs`). Five vectors traced to the bottom, all clean —
and none of them appear in the report, so the time wasn't wasted:

- **reserve vs real balance** — synced via `add_reserve`/`sub_reserve`, and every
  exit point double-checks `reserve >= X && token_vault.amount >= X`.
- **account / oracle spoofing** — every account chained by `address =`/seeds:
  `price_update → wooracle.price_update → woopool.wooracle`. No arbitrary Pyth
  feed can be injected.
- **price manipulation via `post_price`** — the EVM attack. `post_price` doesn't
  clamp on write, but `get_price` clamps on read against Pyth:
  `clo*(1-bound) <= wo_price <= clo*(1+bound)`, else `feasible=false` and the
  swap reverts. Poisoning the stored price is bounded.
- **decimal scale** — `price_decimals` is admin-set and free, but the formula
  normalizes dimensionally at every step, so scale only breaks under admin
  misconfig (trust).
- **rounding between legs** — `checked_mul_div` truncates down; the fee uses
  round-up. All rounding favors the pool. A swap-and-reverse cycle returns
  strictly less. No extraction.

The analysis of the swap was correct. The failure wasn't wrong depth — it was
incomplete breadth.

## What I missed, and why

Three of the four findings live in `rebate_manager` — a program I never opened,
because I anchored on the swap from day one. The fourth was on my surface and I
dismissed it one verification step too early.

### [High] Rebate vault transfers always fail — missing bump seed

`transfer_from_vault_to_owner` signs the CPI with `&[&rebate_manager.seeds()]`,
and `seeds()` returns `[&[u8]; 2]` — two elements, no bump. The `RebateManager`
struct has no `bump` field to supply one. `invoke_signed` derives an address
that doesn't match the real PDA, so `token::transfer` reverts every time. Rebate
fees enter the vault and can never be claimed — permanent DoS.

*Caught it myself once pointed at `claim_rebate_fee.rs`.* New class for the
catalog: **signer seeds without the bump → PDA CPI always reverts → funds
stranded.** Detection: any `new_with_signer` whose seeds don't end in `&[bump]`,
or any PDA struct that doesn't store its `bump`.

### [Medium] Anyone can seize a token's rebate manager — init front-running

`create_rebate_manager` derives the PDA from `[SEED, quote_token_mint]` — no
creator identity — with no authority gate (`authority` is any `Signer`), and the
creator stores itself as `authority`. Since `init` allows exactly one per quote
token, an attacker creates USDC's rebate manager before the team and controls its
rebates; the legitimate `init` then reverts.

*Caught it myself once pointed at the file.* Catalog class (Solana version of the
EVM "first depositor"): **PDA seeds without the owner identity + init with no
authority gate → initialization front-running.**

### [High] Quote pools not enforced to share base/quote token — had it, dismissed it

On my surface. When I traced the swap's account constraints I checked that
`woopool_quote` was anchored by PDA seeds and concluded "account confusion
covered." The real finding is that the constraints don't enforce the *coherence*
of base/quote token across the three pools. I verified the accounts were anchored
but not that the cross-pool coherence constraints were complete — dismissed a
vector that needed one more step of scrutiny.

### [Medium] Rebate authority can't claim — incorrect constraint

In `rebate_manager`, never opened.

## Lessons

1. **Coverage is the whole scope, not the whole main file.** I covered the swap
   exhaustively and treated that as coverage. The scope had a second program;
   3 of 4 findings were there. Before going deep on anything, every file in scope
   gets at least one read. This is the exact lesson Pump Science already taught
   (both Highs in files I never opened). Twice now.
2. **Dismissing needs the same rigor as asserting.** I closed `woopool_quote`
   after confirming the accounts were PDA-anchored, without confirming the
   coherence constraints were complete. "The accounts are anchored" is not "the
   constraints are sufficient."
3. **Two new Solana-specific classes.** Missing bump in signer seeds, and
   owner-less PDA seeds enabling init front-running. Neither exists in Solidity;
   both pay. This is where specializing on the Rust/Solana frontier converts to
   findings an EVM auditor walks past.
