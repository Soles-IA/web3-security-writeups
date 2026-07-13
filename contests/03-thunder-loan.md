# Thunder Loan Audit (CodeHawks First Flight #7)

Audit of an upgradeable flash loan protocol (Solidity 0.8.20). Four HIGH findings, all with executable PoCs.

## Findings

### [High] 1. deposit() inflates the exchange rate
deposit() calls updateExchangeRate() as if a fee were earned, inflating the rate
on a plain deposit with no real yield. The protocol then accounts for more
underlying than it holds, breaking redeem solvency. PoC: rate 1e18 -> 1.003e18.

### [High] 2. Storage collision on upgrade
ThunderLoanUpgraded removes s_feePrecision and makes FEE_PRECISION a constant,
shifting s_flashLoanFee into the old s_feePrecision slot. After upgrade the fee is
corrupted from 3e15 to 1e18, breaking flash loans. PoC confirms fee 3e15 -> 1e18.

### [High] 3. Manipulable spot-price oracle
The oracle reads the instantaneous TSwap spot price with no TWAP/staleness guard.
An attacker moves the DEX price (flash-loan funded) to pay a near-zero fee.
PoC: fee drops 1000x when the reported price drops 1000x.

### [High] 4. Flash loan "repaid" via deposit() (Side Entrance)
flashloan() verifies repayment only by the assetToken balance, which deposit()
also increases — while minting AssetTokens to the caller. The attacker deposits
instead of repaying, then redeems to steal the funds. PoC: attacker 0.3 -> 100.3.

## Lessons
Yield accounting must reflect real fees only; upgradeable storage layout must be
preserved across versions; never use a DEX spot price as an oracle (use TWAP /
Chainlink); repayment checks based on raw balance can be satisfied through
alternate deposit paths (Side Entrance pattern).
