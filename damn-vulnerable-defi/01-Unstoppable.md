# Unstoppable (Damn Vulnerable DeFi #1)

**Vulnerability class:** Denial of Service via a fragile balance invariant
(forced token donation).

## The goal
Not to steal funds — to make the vault's flash-loan feature permanently inoperable.

## The flaw
Inside flashLoan the vault enforces:
`totalAssets()` is the raw token balance, which anyone can change via a direct
ERC20 transfer (no shares minted). Breaking the equality once bricks every future
flash loan permanently.

## The exploit
## The fix
Remove the strict equality check. The flash loan's integrity is already guaranteed
by pulling amount + fee back from the borrower. A vault must never tie a strict
invariant to a balance that is manipulable from outside.

## Lesson
A contract must never assume balanceOf(this) equals its internal accounting.
Forced-donation attacks have caused real losses in production.
