# Reentrance (Ethernaut #10)

**Vulnerability class:** Reentrancy — external interaction before state update.

## The flaw
`withdraw()` sends ETH before decrementing the caller's balance. The `call`
hands control to the recipient, whose `receive()` can re-enter `withdraw()` while
the balance check still passes, looping until the contract is drained.

## The exploit
Attacking with 1 ETH against a vault holding 5 ETH yields ~6 ETH.

## Version note
Reproduced in 0.8.x the exploit reverts on arithmetic underflow — 0.8.0+ added
built-in overflow protection (the old SafeMath role). An `unchecked` block
emulates pre-0.8.0 behavior. Lesson: the compiler version changes which
vulnerabilities exist.

## The fix
Checks-Effects-Interactions: validate, update state, THEN interact.
## Lesson
Any external call can hand control to attacker code. Update state before the call,
never after. This caused The DAO hack (2016).
