# StakeFlow (Solana Audit Arena, Week 1)

First full audit cycle on a Solana/Anchor program. Liquid + locked staking
protocol, Anchor 0.32.1 with Token-2022, 1655 lines, 16 instructions.
Contest window closed; audited blind, then compared against the published
judge report (Frank Castle, 100+ audited protocols).

Result: 0 of 6 findings matched. One vector was developed to a working PoC and
turned out to be a trust assumption, not a bug. Two executable PoCs written.
The real value was learning where my severity judgment diverges from an expert's.

## Analyzed, technically real, not a valid finding

### Insolvency via rebalance_pools + withdraw_reserves
`unstake_liquid` prices redemptions off `config.total_staked` (an internal
counter), while the tokens are custodied in `stake_vault`. `rebalance_pools`
moves tokens out of the stake vault and `withdraw_reserves` sends them out of
the protocol — neither touches `total_staked`. No solvency invariant exists
anywhere in the program (verified by grep: `total_staked` appears in 11 places,
none of them a check against the vault balance).

PoC (`poc/poc-insolvency.ts`) reproduces it end to end:
Alice holds 1000 stX the protocol says are backed, and cannot redeem them.

**Why it isn't a finding:** the actor that triggers it is the liquidity manager,
a trusted role. I built the counter-argument that an *honest* LM causes the same
outcome while doing its declared job (yield farming), so no malicious actor is
required. The judge classified it on the trust side anyway. Under Sherlock-style
rules — and the Arena's — trusted roles exercising their declared powers are out
of scope, regardless of consequence.

## Missed (the real lessons)

- **[F-01] Critical** — double reward claim: `unstake_locked` pays rewards
  without consulting `reward_debt`, which `claim_rewards` maintains. Two exits,
  one ignores the shared counter.
- **[F-02] Critical** — reward inflation: `partial_unstake` scales debt with
  integer division that truncates *downward on a debt*, so each cycle "forgets"
  a token. 499 cycles extract ~396 tokens from 4 legitimate ones.
- **[F-03] High** — `deposit_yield` adds tokens without updating `total_staked`.
- **[F-04] High** — inflation attack: stX can be burned directly via SPL Token,
  collapsing `supply` to 1 and breaking the exchange rate. **This was on my own
  hypothesis list and I abandoned it** to pursue the rebalance path.
- **[F-05] Medium** — `StakeLiquid`/`UnstakeLiquid` exceed the 4096-byte BPF
  stack frame. Compiles and deploys; reverts at runtime.
- **[F-06] Medium** — reward rate changes apply retroactively.

PoC for F-04 written after reading the report (`poc/poc-f04-inflation.ts`),
reproducing the attack with the judge's own numbers:
Note: the truncation-to-zero only materializes with small units. With 6 decimals
the victim receives dust (0.4995 stX) rather than zero — the attack still
misprices them, but the failure mode differs from the one described in the report.

## Lessons / blind spots

1. **Technically true is not the same as valid.** The insolvency reproduces in a
   test and still isn't reportable. The first question on any hypothesis is
   *who triggers this* — if the answer is a trusted role, stop there.
2. **Don't marry a hypothesis.** I had three candidates; F-04 was among them and
   I dropped it for the one that turned out to be trust. Probe all of them
   cheaply before committing to one.
3. **Anchor covers the classic Solana classes for free.** Signer, owner, PDA and
   type-confusion checks come from the constraints. In Anchor programs the
   findings that pay are business logic (my Solidity instinct transfers) plus
   what Anchor does *not* cover: overflow, lamports/rent, arbitrary CPI, and
   platform limits like F-05.
4. **Executing refutes or confirms; reasoning alone does neither.** Both PoCs
   surfaced details the analysis had not anticipated.
