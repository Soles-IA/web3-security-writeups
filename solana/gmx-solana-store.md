# GMX-Solana — store program (Immunefi live bug bounty) — in progress

Live bug bounty on Immunefi (project: GMTrade), core program of the protocol
audited in [treasury](./gmx-solana-treasury.md). `gmsol-store` is the market/
order/position/GLV engine — 38,580 lines across ~130 public instructions,
roughly 12x the size of treasury. This is a multi-session undertaking; what
follows is progress after the first session, not a completed audit.

## Method for a program this size

Full line-by-line coverage before depth (the method used on WOOFi, Pump
Science, treasury) doesn't scale to 38.6k lines in a reasonable number of
sessions. Adapted approach: build the complete instruction inventory first,
classify by suspicion, then go deep on the highest-suspicion candidates
before doing anything else.

Classification of the 130 instructions:
- **Read-only** (`get_market_status`, `token_decimals`, `has_role`, etc.) —
  zero risk by definition, skipped.
- **User-facing by design** (`create_deposit`, `create_order_v2`,
  `create_shift`, `request_gt_exchange`, referral-code flow) — no role
  expected; the question here is accounting correctness under attacker-chosen
  parameters, not access control. Not yet probed this session.
- **Role-gated via `#[access_control(...)]`** — the majority of state-changing
  instructions. Lower priority per the trust filter, same as every prior audit.
- **No visible gate at the `lib.rs` dispatch level** — five candidates stood
  out and got first attention this session.

## The five candidates, all traced and closed

**`initialize_callback_authority`** — `CALLBACK_AUTHORITY_SEED`-only PDA,
`init`-gated, no role. Front-running the creation is possible, but
`CallbackAuthority` stores nothing but its own bump — no creator identity, no
privilege tied to who initializes it. It's a generic signing PDA (same role
as Anchor's `event_authority` convention), functionally identical regardless
of who created it. Sound.

**The callback mechanism end-to-end** (`order.rs`, `execute_order.rs`) — the
architectural twin of Pump Science's arbitrary-CPI pattern: an
`Option<Interface<CallbackInterface>>` account, caller-supplied at execution
time. Closed once traced fully: `ActionHeader` stores `callback_program_id:
Pubkey`, set once at order creation (`set_callback`, called by the order's
owner). Before invoking, `validate_general_callback()` checks the
`callback_program` account passed at *execution* time against that stored
value. An order keeper executing later cannot substitute their own callback
program — only the program the owner declared at creation can ever run.

**`claim_fees_from_market`** — no Anchor role macro, `authority: Signer` with
no visible constraint. Closed by reading the handler body:
`validate_claim_fees_address(authority.key)` checks it against the store's
registered treasury receiver, with the doc comment "Only the receiver of
treasury can claim fees." The gate exists — it's a manual validation inside
the function, not an Anchor-visible constraint.

**`market_config_buffer` trio** (`initialize`/`set_authority`/`push`/`close`)
— a buffer is a private per-user draft (`buffer.authority = creator` on
init), and every mutating instruction on an existing buffer carries `has_one
= authority @ PermissionDenied`. Creating your own buffer confers no access to
anyone else's. Sound.

**`update_order_v2`** — `owner: Signer` tied by `constraint = order.header.owner
== owner.key() @ OwnerMismatched`, plus store/market mismatch checks and a
pending-state check. Textbook identity binding. Sound.

## The method lesson that mattered most this session

**Absence of `#[access_control]` is not absence of protection.** Roughly half
the real access checks in this program live either in a plain `has_one`
constraint on the Anchor accounts struct, or as a manual `validate_*()` call
inside the instruction handler body — not as the visible macro. Grepping for
`access_control` alone gives an incomplete and misleading map. Every
candidate this session required reading the full handler body, not just the
struct, before it could be classified as sound or not.

## What remains (most of the program)

This session covered five instructions out of 130 — the access-control-shaped
candidates from the inventory pass. The bulk of the actual logic is
untouched:

- **Order execution core**: `ops/order.rs` (2011 lines), `exchange/order.rs`
  (1190), `exchange/execute_order.rs` (959) — increase/decrease/liquidate/ADL
  mechanics, exactly where the README's keeper known-issues live (price
  timestamp staleness, execution ordering).
- **GLV subsystem**: `ops/glv.rs` (1522), `states/glv.rs` (1157), plus
  deposit/withdrawal/shift instructions — has its own documented known issue
  (utilization-manipulation shift exploit).
- **Market accounting core**: `states/market/mod.rs`, `config.rs`, `model.rs`,
  `revertible/market.rs` — the actual pool/pricing state.
- **Oracle and price handling**: `states/oracle/mod.rs`.
- **User-facing instructions**: not yet checked for accounting-class bugs
  (the catalog's "field never reaches state," "two paths to funds," rounding
  direction) — only checked, so far, for the access-control question.

None of the protocol's own documented known issues (keeper reordering, price
impact edge cases, GLV shift) have been probed yet — they live in the
untouched two-thirds of the program.
