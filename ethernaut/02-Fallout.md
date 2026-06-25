# Fallout (Ethernaut #2)

**Vulnerability class:** Unprotected initialization — a constructor that isn't one.

## The flaw
In Solidity ^0.6.0 the constructor used the contract's name. The contract is
`Fallout`, but the intended constructor is named `Fal1out` (digit 1 instead of
letter l). The compiler does not treat it as a constructor — it's a public
function anyone can call to become owner.

## The exploit
## The fix
Modern Solidity uses the `constructor` keyword, removing this footgun. But the
general class — unprotected initialization — survives in upgradeable proxies
where an unguarded initialize() lets an attacker seize control.

## Lesson
Read critical identifiers character by character. The difference between l and 1
is the entire vulnerability.
