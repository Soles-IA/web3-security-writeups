# Reentrance (Ethernaut #10)

**Vulnerability class:** Reentrancy — external interaction before state update.

## The target

```solidity
function withdraw(uint256 _amount) public {
    if (balances[msg.sender] >= _amount) {          // 1. check
        (bool result, ) = msg.sender.call{value: _amount}("");  // 2. interaction (sends ETH)
        if (result) { _amount; }
        balances[msg.sender] -= _amount;            // 3. effect (updates state) — TOO LATE
    }
}
```

## The flaw

The function sends ETH (step 2) **before** updating the caller's balance
(step 3). The `call` hands control to the recipient's code. If the recipient is
a malicious contract, its `receive()` can call `withdraw()` again — and because
the balance hasn't been decremented yet, the check in step 1 still passes. The
attacker loops this until the contract is drained.

## The exploit

The attacker is a contract whose `receive()` re-enters while funds remain:

```solidity
receive() external payable {
    if (address(target).balance >= amount) {
        target.withdraw(amount);   // re-enter before our balance is zeroed
    }
}
```

Funding the vault with 5 ETH from other users and attacking with 1 ETH, the
attacker walks away with ~6 ETH. The Foundry test asserts the vault ends at zero
and the attacker's balance exceeds its initial 1 ETH.

### A note on Solidity versions

The original challenge targeted 0.6.0. Reproduced naively in 0.8.x, the exploit
**reverts** with an arithmetic underflow, because 0.8.0+ added built-in
overflow/underflow protection — the very thing that, pre-0.8.0, required the
`SafeMath` library. To reproduce the classic reentrancy I wrapped the subtraction
in an `unchecked` block to emulate the old behavior. This is itself an audit
lesson: **the compiler version changes which vulnerabilities exist.**

## The fix

Follow **Checks-Effects-Interactions**: validate, then update state, then
interact with the outside world.

```solidity
require(balances[msg.sender] >= _amount);   // checks
balances[msg.sender] -= _amount;            // effects (FIRST)
(bool ok, ) = msg.sender.call{value: _amount}("");  // interactions (LAST)
require(ok);
```

With the balance zeroed before the external call, a re-entrant call fails the
check. A `nonReentrant` guard is a complementary defense.

## Lesson

Any external call can hand control to attacker code. State must be fully updated
**before** that call, never after. This is the bug that caused The DAO hack (2016)
and still appears in DeFi today.
