# Fallout (Ethernaut #2)

**Vulnerability class:** Unprotected initialization — a constructor that isn't one.

## The target

The contract is written in Solidity `^0.6.0`, where a constructor was declared
using the **same name as the contract**. The contract is named `Fallout`, and
the intended constructor looks like this:

```solidity
/* constructor */
function Fal1out() public payable {
    owner = msg.sender;
    allocations[owner] = msg.value;
}
```

## The flaw

The function is named `Fal1out` — with the digit **1** instead of the letter
**l**. Visually almost identical, but to the compiler these are different names.
Because the name does not match the contract name `Fallout`, the compiler does
**not** treat it as a constructor. It is just an ordinary public function that
anyone can call, at any time, to set themselves as `owner`.

## The exploit

```solidity
vm.prank(attacker);
target.Fal1out();           // anyone can call the fake "constructor"
assertEq(target.owner(), attacker);
```

A single call takes ownership. (In the Foundry test, the legacy 0.6.0 contract is
reached through an interface and `deployCode`, so the modern test and the old
contract each compile under their own Solidity version.)

## The fix

Modern Solidity removes this exact footgun by using the `constructor` keyword
instead of a name-matched function. But the general class — **unprotected
initialization functions** — is still alive in upgradeable (proxy) contracts,
where an `initialize()` left without an access guard lets an attacker seize
control. The fix is always the same: initialization must run exactly once and be
protected against external re-invocation.

## Lesson

Read critical identifiers character by character; never trust that code "looks
right." A one-character difference between `l` and `1` is the entire vulnerability.
