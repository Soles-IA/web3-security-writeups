# GMX-Solana — treasury program (Immunefi live bug bounty)

Live bug bounty on Immunefi (project: GMTrade), not a closed contest — first
pass against a program where a valid finding pays real money on submission,
not a shadow audit against a published verdict. Solana/Anchor perpetuals
protocol inspired by GMX V2, repo `gmsol-labs/gmx-solana`. Six professional
audit rounds over fourteen months (Sherlock Dec 2024; Zenith Mar/Jun/Jul/Aug
2025 and Jan 2026) — a heavily hardened codebase, closer in posture to Tare
than to WOOFi or Pump Science.

Full protocol is ~45k lines across five programs (`store` 38.6k, `treasury`
3k, `timelock` 1.6k, `competition` 0.8k, `liquidity-provider` 1.5k). Given the
size, this pass scoped to `treasury` alone — the smallest standalone program,
comparable in size to Tare, where full coverage was actually achievable in
one sitting. `store` (the market/order/position core) is a multi-session
undertaking on its own and is left for a future pass.

Result: no reportable findings on treasury's own surface. One mechanism
(callback CPI) traced to the boundary where it crosses into `gmsol-store` and
flagged as pending rather than followed further, per the coverage-before-depth
rule.

## Inventory

16 public instructions in `lib.rs`. 14 gated by `#[access_control(CpiAuthenticate::only(&ctx, roles::X))]`
with roles `TREASURY_OWNER/ADMIN/KEEPER/WITHDRAWER`. Two have no visible gate
at the `lib.rs` level — those got first priority, since ungated-looking
surface is exactly where the untrusted actor might reach in.

## Hypotheses traced to ground

**`complete_gt_exchange`** — no role gate visible; caller is a bare `Signer`.
Reads `remaining_accounts` split positionally into `tokens`/`vaults`/`targets`
by `gt_bank.num_tokens()`. Looked like the catalog's #1 Solana class (account
param not validated against source of truth). It isn't: each slot carries its
own check — `require_keys_eq!(mint.key, token)`, `validate_associated_token_account`
for the vault, and `require_keys_eq!(authority(target), owner_address)` for
the destination. The caller can only route funds to an account *they*
control. The `exchange` being closed is a PDA seeded on
`[GtExchange::SEED, vault, owner]` with `has_one = owner` — an attacker
supplying someone else's exchange either fails the seed derivation or fails
the destination-authority check. Sound.

**`initialize_config`** — no role gate; `payer: Signer` with no constraint.
PDA is `[Config::SEED, store]`, one per store, `init`-gated (fails if it
exists) — textbook init front-running setup, the same class caught in WOOFi's
rebate manager. Here the blast radius is smaller: `initialize_config` also
attempts to register a `receiver` via CPI to the store program's
`accept_receiver`, but that CPI carries `constraint = next_receiver.key() ==
store.load()?.next_receiver()` — a two-step propose/accept pattern. The store
must have already designated this exact PDA as `next_receiver` (an admin
action elsewhere) for the CPI to succeed. An attacker front-running the
`init` cannot hijack the fund-receiving role; worst case is a configuration
DoS (the legitimate team can't create *this* config again), not a fund
capture. Noted as Low/Info-worthy per the "when in doubt, report the
observation" habit — not discarded outright.

**`withdraw_from_treasury_vault`** (`TREASURY_WITHDRAWER`) — trust-gated, so
checked only for third-party harm beyond the role's declared function. The
`decimals: u8` parameter looked like the classic decimal-manipulation vector,
but the transfer uses SPL's `transfer_checked`, which validates `decimals`
against the mint internally and reverts on mismatch — the vector is
neutralized by the primitive itself, not by treasury's own code. No
parallel counter to desync either: `treasury_vault` is a plain token account,
its balance *is* the source of truth, so the "counter vs. real balance" class
doesn't apply here (unlike StakeFlow, which had a separate `reserve` field).
Full-vault withdrawal by the role is the role's declared function, not
escalation.

**`claim_fees`** (`TREASURY_KEEPER`) — `min_amount` is slippage protection,
not an identity check. `market`/`vault` are `UncheckedAccount`s validated "by
CPI" in `gmsol-store` (out of this pass's scope). Destination is hard-locked:
`receiver_vault` is owned by a PDA seeded on the config, so the keeper
controls *when* fees are claimed but never *where* they land. Sound on
treasury's side; the open question (are `market`/`vault` properly validated
inside `gmsol-store`'s `claim_fees_from_market`) belongs to a `store` pass.

**`create_swap_v2`** (`TREASURY_KEEPER`) — direction is constrained
(`is_deposit_allowed` false for swap-in token, true for swap-out), so the
treasury can only convert pass-through tokens into tokens it wants to
accumulate, never the reverse. But four callback accounts —
`callback_authority`, `callback_program`, `callback_shared_data_account`,
`callback_partitioned_data_account` — are all `Option<UncheckedAccount>`,
forwarded via `remaining_accounts` into a CPI to `gmsol-store`'s
`create_order_v2`. This is architecturally the same shape as Pump Science's
arbitrary-CPI pattern (an unchecked, caller-influenced program invoked with
authority attached). Whether it's exploitable depends entirely on how
`create_order_v2` validates `callback_program` inside `gmsol-store` — code
this pass didn't cover. **Flagged as pending, not resolved.**

## Lessons

1. **Ungated-looking instructions deserve first attention, but "ungated" isn't
   "unprotected."** Both instructions without a role gate at the dispatch
   level turned out to have their real defense one or two layers deeper (PDA
   seeds tied to identity; a two-step accept pattern requiring prior admin
   action). The absence of `#[access_control]` is a prompt to look harder, not
   a verdict.
2. **`transfer_checked` neutralizes the decimals-manipulation class by
   design.** Worth a permanent catalog entry: seeing `transfer_checked` (vs.
   plain `transfer`) means that specific vector can usually be skipped.
3. **Responsibility crosses program boundaries, and coverage has to stop at
   the edge deliberately, not by accident.** The callback mechanism in
   `create_swap_v2` is real surface, but resolving it means auditing
   `gmsol-store` — a 38k-line program. Naming the boundary and moving on,
   rather than either chasing it half-depth or pretending it's resolved, is
   the same coverage discipline that cost two Highs in Pump Science and
   WOOFi when it wasn't followed.
4. **Matching the toolchain to the target ahead of time removed a whole class
   of friction.** This protocol pins Anchor 0.31.1 and Solana v2.1.21 — the
   exact versions already working from the PoC template — so this pass spent
   zero time on environment setup, for the first time this month.
