# Naive Receiver (Damn Vulnerable DeFi #2)

**Vulnerability classes:** (1) Missing initiator validation in a flash-loan
receiver, and (2) `_msgSender()` spoofing via ERC-2771 meta-transactions combined
with Multicall. Two bugs chained into a single atomic attack.

## The goal

Drain both the FlashLoanReceiver (10 WETH) and the NaiveReceiverPool (1000 WETH)
— 1010 WETH total — to a recovery address, in at most two player transactions.
The solution does it in one.

## Vulnerability 1 — Draining the receiver

The pool charges a FIXED_FEE = 1 WETH per flash loan, regardless of amount. The
receiver's onFlashLoan only checks that the caller is the pool — it never
validates who initiated the loan. So anyone can force the receiver to take loans.
Ten flash loans of 0 WETH each charge it 1 WETH in fees, draining its 10 WETH.

## Vulnerability 2 — Draining the pool

The pool identifies the user via a meta-transaction pattern: _msgSender() trusts
the last 20 bytes of calldata when msg.sender == trustedForwarder. withdraw() uses
deposits[_msgSender()] -= amount, and the pool inherits Multicall. By routing a
call through the forwarder and embedding a withdraw sub-call whose calldata I
manually terminate with the feeReceiver's address, _msgSender() reads that planted
address and believes the feeReceiver is withdrawing.

All 11 calls are bundled into one multicall, sent through forwarder.execute with a
valid EIP-712 signature from the player. The forwarder is satisfied (the player
signed legitimately), but the inner payload spoofs the pool's identity check.

## The fix

- The receiver must validate the loan initiator (first onFlashLoan parameter),
  not just the caller, and reject loans it didn't authorize.
- The pool must not derive authentication identity from raw calldata bytes that
  can be forged. Combining a trusted-forwarder _msgSender() with an open Multicall
  lets an attacker append an arbitrary address to a sub-call. Restrict what can be
  invoked through the forwarder, or don't trust calldata-derived identity for
  fund-moving operations.

## Lesson

Two individually small issues — a receiver that doesn't check the initiator and an
identity derived from calldata — combine into a total drain. Real audit value is
in spotting how independent weaknesses chain into one atomic exploit.
