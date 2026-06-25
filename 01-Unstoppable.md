# Unstoppable (Damn Vulnerable DeFi #1)

**Vulnerability class:** Denial of Service via a fragile balance invariant
(forced token donation).

## The goal

Unlike a typical exploit, the objective here is **not** to steal funds — it's to
make the vault's flash-loan feature permanently inoperable. The vault thinks it
is "unstoppable"; the task is to stop it.

## The target

The vault is an ERC4626 tokenized vault offering flash loans. Inside `flashLoan`:

```solidity
uint256 balanceBefore = totalAssets();                       // real token balance
if (convertToShares(totalSupply) != balanceBefore) revert InvalidBalance();
```

It enforces a strict equality between two quantities it assumes always match:

- `totalAssets()` = `asset.balanceOf(address(this))` — the **real** token balance.
- `totalSupply` = the vault's internal share accounting.

## The flaw

`totalSupply` only changes through the vault's own `deposit` / `withdraw`
functions, which mint or burn shares in lockstep. But `totalAssets()` is just the
contract's raw token balance — and **anyone can change that** by sending tokens
directly via the ERC20 `transfer`, with no shares minted in return.

Break the equality once and the `require` reverts on every future flash loan —
permanently, since the donated tokens can't be removed without going through the
vault's own functions.

## The exploit

```solidity
function test_unstoppable() public checkSolvedByPlayer {
    token.transfer(address(vault), 1);   // one direct transfer breaks the invariant forever
}
```

A single 1-wei token transfer desynchronizes `totalAssets` from `totalSupply`,
and the flash loan is bricked. The challenge's monitor then detects the broken
flash loan and pauses the vault — satisfying the success condition.

## The fix

Remove the `convertToShares(totalSupply) != balanceBefore` check entirely. It
provides no real security and creates the DoS vector. A flash loan's integrity is
already guaranteed by pulling `amount + fee` back from the borrower at the end of
the call. A vault should never tie a strict invariant to its raw token balance,
which is manipulable from the outside; if it needs internal accounting, it should
track it independently of `balanceOf(this)`.

## Lesson

A contract must never assume that `balanceOf(this)` equals its internal
accounting. Anyone can donate tokens to any address and break that assumption.
"Forced donation" attacks have caused real losses in production protocols.
