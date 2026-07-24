# Tare (Sherlock audit contest, July 2026)

Live contest on a production RWA lending protocol. Solidity 0.8.33, Avalanche
C-Chain, USDC only. ~3900 lines of implementation across Loans, LoansLedger,
LoansNFT, LoansExchange, PortfolioVault, NavCalculator and Safe modules.

Result: no reportable findings. Full sweep of the untrusted attack surface,
seven hypotheses probed to the code, plus invariant fuzzing on the one property
the team documented as unverified on-chain. Every vector died at the same wall.
Documented because knowing why a codebase resists is worth as much as a finding.

## Scope discipline

The contest README declares Guardian, Admin, Servicer, Originator, Portfolio
Manager, Investor Manager and Calculating Agent as **trusted**. Value-setting
functions intentionally carry no economic bounds because only those roles reach
them. What is in scope:

> "Borrower, Investor and Servicer are trusted within their individual loan.
> However, if they can hurt other loans/users, this can be considered valid."

So the target invariant is **isolation between loans**, and any unbounded input
reachable by a Borrower, Investor or arbitrary caller.

The repo also ships a `SECURITY.md` with **31 declared known issues**, an
`invariants.md` tagging every property as enforced `[E]`, derived `[D]`,
conditional `[C]` or operational `[O]`, and links to prior audits. That is an
unusually well-prepared codebase, and it sets the bar accordingly.

## Hypotheses probed and why each died

**NAV freshness omission.** `invariants.md` flags the master freshness property
as maintained by "a manual conjunction ... a single omission is invisible until
mispricing happens". Cross-referenced every `_requireIdleNav()` against every
`_invalidateNav()`: three call sites require idle without invalidating
(`setExchange`, `acceptSaleOffer`, `transferLoans`). Two of them move NFTs, so
`loansNFT.ownershipNonce` bumps and `_requireFreshNav` catches it; the third
touches nothing that feeds NAV. Two complementary defences, correctly split.

**Phantom loans in the curated NAV list.** A loan sold via `LoansExchange.acceptOffer`
leaves the vault without the vault participating in the transaction. It stays in
`_navLoanIds`. But `updateNav` checks `ownerOf` per loan as it walks the list and
evicts foreign entries (with `try/catch` covering burned tokens), so the list
self-heals before valuation.

**Duplicate entries in the curated list.** `_addLoanToNav` opens with
`if (_navLoanIndex[loanId] != 0) return;`, and the swap-and-pop in
`_removeLoanFromNav` correctly reindexes the moved element.

**Seller draining a listed loan before settlement.** The exchange's
anti-front-running property rests on external invariants it does not check
itself. Traced them into `Loans.investorWithdraw`: for a locked loan the
recipient is forced to `msg.sender == unlocker`, and the batch path requires
uniform investor *and* uniform unlocker across all loans — so locked and
unlocked cannot be mixed. The exchange holds no currency and never calls
`investorWithdraw` (verified by grep across `contracts/`).

**Double-counting cash mid-NAV-cycle.** `updateNav` is batched, so a withdrawal
between batches would add cash to the vault's balance while `pendingNav` still
counted it inside the loan. The only caller of `investorWithdraw` on vault-owned
loans is `PortfolioVault.collectCashflows`, which is gated by `_requireIdleNav()`
and calls `_invalidateNav()`. Not reachable mid-cycle except by admin.

**Locked NFT unrecoverable even by the guardian.** `forceTransfer` rejects locked
tokens and only the unlocker can `unlock`. Real, and *declared*: known issue #1
states the loss runs "until the lock is removed (which the unlocker alone
controls)", and `invariants.md` §4 documents the refusal as deliberate so
guardian recovery can never break exchange escrow.

**Servicer inflating NAV via `createLedgerEntries`.** Mechanically sound, and
covered three times over: known issue #5, trust assumption T-4, and the `[C]`
tag on every invariant that these escape hatches can break.

## Invariant fuzzing

`invariants.md` #1 marks the accounting equation as `[D]` — "ledger.md lists this
as invariant #1 but the chain never verifies it". Wrote a Foundry invariant test
reusing the team's own `_getLoanTotalBalance` helper (21 ledger accounts summed
to zero), with a handler restricted to untrusted entry points only (`pay`,
`investorWithdraw`), deliberately excluding `createLedgerEntries`, `chargeMiscFee`
and `updateLoanData` so a break would be a valid finding rather than a trusted-role
artifact.
Zero reverts means every call executed rather than bouncing off a require. The
zero-sum holds under 128k randomized sequences. Worth noting the `[D]` tag means
*the contract* does not verify it at runtime — the team's own suite asserts it in
28 tests via an `accountingEquationHolds` modifier.

## Thinking like an attacker: the NAV under concurrency

After the read-through, I asked a different question — not "what haven't I
checked" but "where would I break this if I had to". Filtering out everything a
trusted role triggers, three zones concentrate the residual weakness:

1. **The non-standard NFT lock/unlocker model** — the one thing the team had to
   invent, so the least covered by prior industry auditing. Closed in `_update`
   (single choke point, validates lock + bumps `ownershipNonce`).
2. **`LoansExchange`** — the only place two untrusted parties transact. Its
   anti-front-running property "rests on external invariants the exchange does
   not check itself". Deslocalized defence, but it holds: `Loans.investorWithdraw`
   forces `recipient = msg.sender` for locked loans.
3. **NAV freshness under concurrency** — `lastNav` is cached, updated in batches,
   via a "manual conjunction" of invalidations the team itself flags as fragile.

Zones 1 and 2 were ruled out by static reading. Zone 3 cannot be — interleaving
matters, and that only surfaces by executing. So I wrote a second invariant test
targeting it.

## Invariant fuzzing #2: share-price arbitrage

Handler exposes only the untrusted vault entry points (`requestDeposit`,
`deposit`, `requestRedeem`, `redeem`, `cancelDepositRequest`) plus a
`pokeNav(batchSize)` with fuzzed batch size — so the fuzzer can interleave
operations *between* NAV batches, which is where a concurrency bug would live.
The mock calculator's loan valuation is fixed once in `setUp` and never touched,
so any share-price movement or solvency deficit comes from vault mechanics, not
the NAV calculation.

Two properties:
- `invariant_solvency`: idle USDC + fixed loan valuation always covers claimable
  redemptions + pending deposits.
- `invariant_sharePriceStable`: with the underlying valuation fixed, the share
  price cannot drift from its initial value beyond rounding.
Both hold. Scope note, because knowing a test's limits is part of the job: the
mock means this does **not** exercise `NavCalculator` internals (covered by
reading) — it exercises the vault's mechanics around the NAV, which is exactly
the zone an attacker would probe.

## Lessons

1. **A documented codebase redirects attention.** Every property `invariants.md`
   flags as a fuzz target is precisely what the team hardened. The bugs, if any,
   live in what nobody wrote down.
2. **"Who triggers this?" comes first.** Seven hypotheses, and the ones that died
   on trust died only after I had developed the mechanism. That check costs
   thirty seconds and should precede the analysis, not follow it.
3. **Never assert an unverified link.** Mid-audit I claimed the exchange could
   reach `investorWithdraw`; a grep across `contracts/` showed it does not. A
   finding built on an invented step is invalid on inspection and costs
   reputation on a platform that tracks it.
4. **No finding is a legitimate professional result.** 31 known issues and prior
   audits mean the accessible surface is already swept. Reporting nothing beats
   reporting a duplicate or an out-of-scope trust issue.
5. **Turn over the last stone with a tool, not an assumption.** Reading rules out
   what you can see; the residual risk lives in interleavings you can't. Asking
   "where would I break this" pointed at NAV concurrency, and only a fuzzer could
   confirm it holds. Closing an audit with "no findings" is honest only once the
   one property you couldn't read has actually been executed.
