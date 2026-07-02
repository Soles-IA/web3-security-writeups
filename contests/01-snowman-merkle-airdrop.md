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

---

## Finding 3 — [Medium] Global `s_earnTimer` causes protocol-wide DoS on earnSnow

**Contract:** Snow.sol · **Function:** earnSnow

### Description
`earnSnow()` gates a 1-token-per-week free claim, but the cooldown `s_earnTimer`
is a single contract-wide variable instead of a per-user mapping. When any user
calls `earnSnow()`, the global timer resets for everyone, so a different user who
never farmed is blocked for a week. Effectively only one user in the whole
protocol can farm per week. Worsened by the fact that `buySnow()` also writes
`s_earnTimer`, and `buySnow(0)` is free — an attacker can keep the timer fresh and
permanently deny farming to all.

### Proof of Concept
A Foundry test confirms it: Alice farms, then Bob (a different address who never
farmed) is immediately reverted with `S__Timer`.

### Recommendation
Make the cooldown per-user: `mapping(address => uint256) s_earnTimer`, keyed by
`msg.sender`. Remove the `s_earnTimer` write from `buySnow()`.

## Finding 4 — [Medium] buySnow traps user ETH when msg.value is non-exact

**Contract:** Snow.sol · **Function:** buySnow

### Description
`buySnow` pays in ETH if `msg.value` exactly equals the price, otherwise charges
WETH. If a user sends a non-zero `msg.value` that isn't exactly the price, they
fall into the else branch: they are charged the full price in WETH **and** the ETH
they sent stays trapped in the contract with no user refund path (only the
collector can sweep it via `collectFee`). Double payment / direct loss of funds.

### Proof of Concept
A Foundry test confirms it: user approves WETH, calls `buySnow{value: 0.1 ether}(1)`,
receives the token, is charged full WETH, and the 0.1 ETH is left stuck in the contract.

### Recommendation
Reject non-matching `msg.value` in the else branch (`require(msg.value == 0)`), or
refund any unused native ETH at the end of the function.

## Finding 5 — [High] mintSnowman has no access control

**Contract:** Snowman.sol · **Function:** mintSnowman

### Description
Snowman NFTs are meant to be minted only by the SnowmanAirdrop contract after it
verifies a claimer's Merkle proof, EIP-712 signature, and Snow balance. The
contract even declares an `SM__NotAllowed()` error, signaling intent to restrict
minting. But `mintSnowman` is `external` with no access control: no onlyOwner, no
check that msg.sender is the airdrop, and the SM__NotAllowed error is never used.
Any address can call it directly and mint arbitrary NFTs.

### Impact
High. Anyone can mint unlimited Snowman NFTs for free — no tokens, no proof, no
signature — completely bypassing the airdrop and rendering the entire
SnowmanAirdrop mechanism meaningless. Missing access control (OWASP #1).

### Proof of Concept
A Foundry test confirms it: an attacker with nothing calls
`mintSnowman(attacker, 1000)` and receives 1000 NFTs.

### Recommendation
Restrict mintSnowman to the airdrop contract (or owner), enforcing it with the
already-declared SM__NotAllowed() error:
`if (msg.sender != i_airdrop) revert SM__NotAllowed();`
