# Web3 Security Writeups

Smart contract security research across EVM (Solidity) and Solana (Rust/Anchor),
with each exploit written from scratch and run against a local chain.

The goal of this repository is not to collect solutions, but to document my own
reasoning when breaking contracts — the vulnerability class, how I spotted it,
the exploit, and the fix a protocol should apply. Discarded hypotheses are
included on purpose: knowing why something is *not* a valid finding is half the
job.

I come from a hands-on DeFi background (deploying and debugging flash-loan and
lending strategies on Arbitrum) and I'm transitioning into security research.

## Audit Contests

| Contest | Platform | Result | Writeup |
|---------|----------|--------|---------|
| Tare | Sherlock, Jul 2026 ($27K) | Full sweep of the untrusted surface + zero-sum invariant fuzzing (128k calls). No reportable findings | [link](./contests/05-tare-sherlock.md) |
| MyCut | CodeHawks First Flight | 1 of 6 H/M, zero invalid reports | [link](./contests/04-mycut.md) |
| Thunder Loan | CodeHawks First Flight | 4 High, all with runnable PoCs | [link](./contests/03-thunder-loan.md) |
| Puppy Raffle | CodeHawks First Flight | 6 findings with runnable PoCs | [link](./contests/02-puppy-raffle.md) |
| Snowman Merkle Airdrop | CodeHawks First Flight | 1 High (unlimited NFT minting), 1 Low (EIP-712 typehash typo) | [link](./contests/01-snowman-merkle-airdrop.md) |

## Solana / Rust (Anchor)

Audits of Solana programs, compared against published expert verdicts where one
exists.

| Protocol | Context | Result | Writeup |
|----------|---------|--------|---------|
| GMX-Solana (store) — in progress | Immunefi live bug bounty (GMTrade) | 5 of 130 instructions traced (access-control candidates); core order/GLV/pricing logic (~35k lines) not yet covered | [link](./solana/gmx-solana-store.md) |
| GMX-Solana (treasury) | Immunefi live bug bounty (GMTrade) — first pass, real payout at stake | Full coverage of the 3k-line treasury program; no findings, callback-CPI mechanism flagged pending against the 38k-line core program | [link](./solana/gmx-solana-treasury.md) |
| Pump Science | Code4rena, Jan 2025 ($20K) — shadow audit | Identified M-01 (last-buy fee mismatch) independently; missed both Highs | [link](./solana/pump-science.md) |
| Orderly Network | Sherlock, 2024 ($27.5K) — shadow audit | Two Highs found independently (mint substitution + withdrawal receiver), both matching sponsor-confirmed issues (#37 + #146) in the official Sherlock report | [link](https://github.com/Soles-IA/web3-security-writeups/tree/main/solana/orderly) |
| WOOFi Swap | Sherlock, Sep 2024 ($21.5K) — shadow audit | Prior pass: caught 2 of 4 Highs (bump-seed DoS, init front-running). In progress: independent re-audit — wooracle-authority candidate open, timestamp candidate dismissed (see folder) | [link](https://github.com/Soles-IA/web3-security-writeups/tree/main/solana/woofi) |
| MissionX | Solana Audit Arena Week 2 — practice | Role-separation bypass (High), duplicate-submitter griefing (Medium) | [link](./solana/missionx-practice.md) |
| StakeFlow | Solana Audit Arena Week 1 — practice | Two executable PoCs; one vector ruled out as trust after comparing with the judge | [link](./solana/stakeflow.md) |

PoCs in [`solana/poc/`](./solana/poc/) target a local validator via
`anchor test`.

## Solana Bug Catalog

A running [checklist of Solana/Anchor bug classes](./solana/bug-catalog.md) with detection signals, distilled from real contests. Read at the start of every audit.

## Methodology

1. **Map the scope** — identify which actors are untrusted before reading code.
   A vector triggered by a trusted role is out of scope regardless of impact.
2. **Read** and trace every place a sensitive variable or privilege is modified.
3. **Hypothesize** the attack: what assumption can be broken from outside?
   Probe every candidate cheaply before committing to one.
4. **Verify** each link with `grep` or an executable PoC. Never assert a step
   that has not been confirmed in the code.
5. **Exploit** it with a test that proves the vulnerability runs.
6. **Bound the impact** to what can be demonstrated, and state explicitly what
   was not verified.
7. **Fix** it: describe the correct design the protocol should have used.

## Exercises

| # | Exercise | Vulnerability class | Source | Writeup |
|---|----------|---------------------|--------|---------|
| 1 | Fallback | Weak access control | Ethernaut | [link](./ethernaut/01-Fallback.md) |
| 2 | Fallout | Unprotected initialization | Ethernaut | [link](./ethernaut/02-Fallout.md) |
| 3 | Reentrance | Reentrancy | Ethernaut | [link](./ethernaut/03-Reentrance.md) |
| 4 | Unstoppable | ERC4626 vault DoS | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/01-Unstoppable.md) |
| 5 | Naive Receiver | Flash-loan fee abuse + _msgSender spoofing | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/02-NaiveReceiver.md) |
| 6 | Truster | Arbitrary call / approve abuse | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/03-Truster.md) |
| 7 | Side Entrance | Balance vs internal accounting mismatch | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/04-SideEntrance.md) |
| 8 | The Rewarder | Double-spend via late state marking (batch) | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/05-TheRewarder.md) |
| 9 | Puppet | Price oracle manipulation (DEX spot) | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/06-Puppet.md) |
| 10 | Selfie | Flash-loan governance attack (instant voting power) | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/07-Selfie.md) |

## Running the exploits

Foundry project for the EVM side:

```bash
git clone --recurse-submodules https://github.com/Soles-IA/web3-security-writeups.git
cd web3-security-writeups
forge test -vv
```

Each exploit is in `test/` and the vulnerable contract in `src/`. The Solana
PoCs live in `solana/poc/` and run with `anchor test` against the corresponding
program.

## Environment

Foundry (Solidity), Anchor 0.31/0.32 built from source (Solana), Solana CLI,
TypeScript PoCs against a local validator.

## Background

Before focusing on security I built and deployed contracts on Arbitrum mainnet
involving Balancer flash loans, Aave V3 (including eMode), and Uniswap V3 swaps.
Debugging real reverts by reading call traces is what pulled me toward
understanding *why* contracts fail — and from there, into security research.
