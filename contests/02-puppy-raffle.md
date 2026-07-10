# Puppy Raffle Audit (CodeHawks First Flight #1)

Audit of a raffle contract (Solidity 0.7.6). Six findings, all with executable PoCs.

## Findings

### [High] 1. Reentrancy in refund
`refund` transfers ETH before zeroing the player slot (violates CEI). An attacker
re-enters from receive() and drains the entire contract. PoC drains 5 ETH to 0.

### [Medium] 2. O(n^2) duplicate check causes DoS
`enterRaffle` checks duplicates with a nested loop. Gas grows quadratically; at
~200 players a single entry nears the block gas limit, blocking new entries.

### [High] 3. Weak on-chain randomness
`selectWinner` derives the winner/rarity from msg.sender, block.timestamp,
block.difficulty — all predictable. PoC computes the winner off-chain; it matches
the actual winner exactly.

### [Medium] 4. totalFees uint64 overflow
`totalFees` is uint64 (max ~18.44 ETH) in Solidity 0.7.6 (no overflow revert). A
100-player raffle produces 20 ETH of fees, wrapping totalFees to ~1.56 ETH and
corrupting fee accounting.

### [Low] 5. getActivePlayerIndex returns ambiguous 0
Returns 0 both for the player at index 0 and for non-participants, making the two
indistinguishable.

### [Medium] 6. withdrawFees permanently blockable
The strict `balance == totalFees` check can be broken forever by forcing ETH via
selfdestruct, locking all fees.

## Lessons
CEI ordering, O(n^2) gas DoS, on-chain randomness weakness, pre-0.8 overflow with
narrow integer types, ambiguous sentinel returns, and brittle strict-equality
balance checks.
