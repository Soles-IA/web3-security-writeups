# MyCut Audit (CodeHawks First Flight)

Audit of a prize-distribution protocol (Solidity ^0.8.20): a ContestManager
deploys Pot contracts that hold rewards; players claim their cut, and after
90 days the owner closes the pot (manager takes 10%, leftover split among claimants).

Result: 1 of 6 H/M found. Zero invalid reports (submissions were sound; two did
not match the judge's catalog). Strong on in-function accounting bugs; weaker on
malformed inputs, cross-contract interactions, and gas DoS.

## Found

### [High] closePot divides leftover by total players instead of claimants  → matched [H-02]
closePot() computes claimantCut = (remainingRewards - managerCut) / i_players.length
but only loops over claimants. When claimants < players, only a fraction of the
leftover is distributed and the rest is locked forever.
Example: 10 players, 700 leftover, 3 claimants -> 259 distributed, 441 locked.
Fix: divide by claimants.length (guard against zero).

## Submitted, sound but unmatched by the judge

### closePot is callable repeatedly
closePot never resets remainingRewards nor sets a "closed" flag, so closeContest
-> closePot can re-run the distribution, re-paying manager and claimants. Fix:
reset remainingRewards = 0 after distribution.

### Unchecked ERC20 transfer return values
Raw transfer/transferFrom with return value ignored; non-standard tokens (USDT-style)
that return false break accounting. Fix: use SafeERC20.

## Missed (the real lessons)

- [H-01] Owner cut gets stuck in ContestManager (cross-contract interaction — funds
  trapped in a contract with no withdrawal path).
- [H-03] Constructor overwrites rewards for DUPLICATE players (malformed input not validated).
- [H-04] Gas-limit DoS via large claimants array (unbounded loop).
- [M-01] Division by zero when claimants.length == 0 (I noted this in a mitigation
  but failed to file it as its own finding — a recurring mistake).
- [M-02] claimCut can run before the pot is funded.

## Lessons / blind spots (consistent across 4 contracts)
1. Always check malformed inputs: duplicates, zeros, empty arrays.
2. Always check cross-contract interactions: can funds get stranded in another contract?
3. Always check loops for gas DoS with many elements.
4. Capitalize every observation as its own finding — don't bury it in a mitigation note.
