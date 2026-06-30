# Snowman Merkle Airdrop (CodeHawks First Flight) — Real Audit Findings

My first findings submitted to a live audit contest (CodeHawks First Flight,
"Snowman Merkle Airdrop"). Real production code with no planted bug — found
through manual review.

## Finding 1 — [High] Missing claim check enables unlimited NFT minting

**Contract:** SnowmanAirdrop.sol · **Function:** claimSnowman

### Description
The airdrop is meant to allow each recipient to claim exactly once, enforced by
the s_hasClaimedSnowman mapping. But claimSnowman writes
s_hasClaimedSnowman[receiver] = true at the end and never reads it at the start.
The mapping is dead code.

The only gate is balanceOf(receiver) == 0, which blocks an immediate second claim
but not a later one: the recipient can re-acquire Snow (earnSnow weekly or
buySnow), restoring their balance to the allocated amount. Since the Merkle leaf
and EIP-712 signature are both bound to amount = balanceOf(receiver), topping the
balance back to exactly the allocation makes the same proof and signature valid
again — no nonce, no replay protection.

### Impact
A recipient can mint an unbounded number of Snowman NFTs from a single
allocation, inflating supply and destroying the fairness of the distribution.

### Proof of Concept
A Foundry test confirms it: Alice claims (1 NFT), tops her balance back to 1 via
earnSnow(), and claims again with the same proof/signature, ending with 2 NFTs.
getClaimStatus(alice) returns true after the first claim, yet the second claim
still succeeds — proving the flag is recorded but never enforced.

### Recommendation
Add a check at the start of claimSnowman (Checks-Effects-Interactions):
if (s_hasClaimedSnowman[receiver]) revert SA__AlreadyClaimed();

## Finding 2 — [Low] Typo in MESSAGE_TYPEHASH breaks EIP-712 compliance

**Contract:** SnowmanAirdrop.sol

### Description
The EIP-712 type string is misspelled: "addres" instead of "address" in
keccak256("SnowmanClaim(addres receiver, uint256 amount)"). The contract is
internally consistent so its own tests pass, but it is not EIP-712 compliant: a
standards-compliant wallet derives a different typehash, produces a different
digest, and a legitimately-signed claim fails _isValidSignature and reverts.

### Impact
Low. No direct loss of funds, but breaks interoperability with compliant signers.

### Recommendation
keccak256("SnowmanClaim(address receiver,uint256 amount)");

## Reflection

Found by manual review of unfamiliar production code. What worked: read the full
claim flow first, then trace each state-changing variable and ask whether it is
actually enforced. The key insight on Finding 1 was rejecting the naive "claim
twice in a row" idea (blocked by the balance check) and finding the real vector:
balance top-up resets all conditions because there is no replay protection. Same
class as a batch double-spend — state written but never checked.
