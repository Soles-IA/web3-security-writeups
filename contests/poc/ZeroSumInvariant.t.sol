// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {Test} from "forge-std/Test.sol";
import {LoansTestBase} from "../setup/LoansTestBase.t.sol";
import {Loans} from "contracts/Loans.sol";
import {MockUSDC} from "test/mocks/USDC.sol";

/// @dev Handler con SOLO operaciones alcanzables por untrusted.
///      Excluye createLedgerEntries / chargeMiscFee / updateLoanData (roles confiables).
contract UntrustedHandler is Test {
  Loans public loans;
  MockUSDC public usdc;
  uint64 public loanId;
  address public borrower;
  address public investor;

  constructor(Loans _loans, MockUSDC _usdc, uint64 _loanId, address _borrower, address _investor) {
    loans = _loans;
    usdc = _usdc;
    loanId = _loanId;
    borrower = _borrower;
    investor = _investor;
  }

  function borrowerPays(uint96 raw, uint48 ts) external {
    int128 amount = int128(uint128(bound(uint256(raw), 1e6, 5_000e6)));
    usdc.mint(borrower, uint256(uint128(amount)));
    vm.startPrank(borrower);
    usdc.approve(address(loans), type(uint256).max);
    try loans.pay(loanId, amount, uint48(bound(uint256(ts), 1, type(uint48).max)), bytes32("fuzz")) {} catch {}
    vm.stopPrank();
  }

  function investorWithdraws(uint48 ts) external {
    uint64[] memory ids = new uint64[](1);
    ids[0] = loanId;
    vm.prank(investor);
    try loans.investorWithdraw(ids, uint48(bound(uint256(ts), 1, type(uint48).max)), bytes32("fuzz")) {} catch {}
  }
}

contract ZeroSumInvariantTest is LoansTestBase {
  UntrustedHandler handler;

  function setUp() public override {
    super.setUp();
    loanId = _createActiveLoan(DEFAULT_TEST_PRINCIPAL);
    handler = new UntrustedHandler(loans, usdc, loanId, borrower, investor);
    targetContract(address(handler));
  }

  /// @dev invariants.md #1 [D]: suma de las 21 cuentas del prestamo == 0.
  ///      Reusa el helper del propio equipo, pero con secuencias aleatorias.
  function invariant_zeroSum() public view {
    assertEq(_getLoanTotalBalance(loanId), 0, "Accounting equation violated");
  }
}
