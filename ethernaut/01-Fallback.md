# Fallback (Ethernaut #1)

**Vulnerability class:** Weak access control — a side-door to ownership.

## The flaw
`withdraw()` is protected with `onlyOwner`, but `receive()` hands over ownership
with trivial conditions (any non-zero ETH + any prior contribution), ignoring the
1000-ETH contribution that supposedly protects ownership.

## The exploit
## The fix
`receive()` should never assign ownership. Ownership transfer belongs in an
explicit, access-controlled function.

## Lesson
Protecting the *use* of a privilege is worthless if another function gives the
privilege away cheaply. Trace every path to a sensitive role.
