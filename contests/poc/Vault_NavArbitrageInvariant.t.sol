// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.33;

import {VaultTestBase} from "./VaultTestBase.t.sol";

contract Vault_NavArbitrageInvariant is VaultTestBase {
  uint256 internal priceAtSetup;
  address[3] internal actors;

  function setUp() public override {
    super.setUp();
    _setupInitialNav(DEFAULT_LOAN_VALUATION);

    actors = [shareholder1, shareholder2, makeAddr("carol")];
    shareToken.grantRole(shareToken.SHAREHOLDER_ROLE(), actors[2]);

    for (uint256 i; i < 2; ++i) {
      _fundShareholder(actors[i], 50_000e6);
      vm.prank(actors[i]);
      vault.requestDeposit(50_000e6, actors[i], actors[i]);
      vm.prank(manager);
      vault.approveDeposit(actors[i], 50_000e6);
      uint256 claimable = vault.maxDeposit(actors[i]);
      vm.prank(actors[i]);
      vault.deposit(claimable, actors[i], actors[i]);
      vm.prank(actors[i]);
      shareToken.approve(address(vault), type(uint256).max);
    }

    priceAtSetup = _sharePrice();

    _fundShareholder(actors[2], 500_000e6);
    vm.prank(actors[2]);
    shareToken.approve(address(vault), type(uint256).max);

    targetContract(address(this));
    bytes4[] memory sel = new bytes4[](6);
    sel[0] = this.h_requestDeposit.selector;
    sel[1] = this.h_approveAndDeposit.selector;
    sel[2] = this.h_requestRedeem.selector;
    sel[3] = this.h_approveAndRedeem.selector;
    sel[4] = this.h_cancelDeposit.selector;
    sel[5] = this.h_pokeNav.selector;
    targetSelector(FuzzSelector({addr: address(this), selectors: sel}));
  }

  function h_requestDeposit(uint256 actorSeed, uint256 amount) external {
    address a = actors[actorSeed % 3];
    amount = bound(amount, 1e6, 100_000e6);
    usdc.mint(a, amount);
    vm.prank(a);
    usdc.approve(address(vault), type(uint256).max);
    vm.prank(a);
    try vault.requestDeposit(amount, a, a) {} catch {}
  }

  function h_approveAndDeposit(uint256 actorSeed) external {
    address a = actors[actorSeed % 3];
    uint256 pending = vault.pendingDepositAssets(a);
    if (pending == 0 || !_navFresh()) return;
    vm.prank(manager);
    try vault.approveDeposit(a, pending) {} catch { return; }
    uint256 claimable = vault.maxDeposit(a);
    if (claimable == 0) return;
    vm.prank(a);
    try vault.deposit(claimable, a, a) {} catch {}
  }

  function h_requestRedeem(uint256 actorSeed, uint256 shares) external {
    address a = actors[actorSeed % 3];
    uint256 bal = shareToken.balanceOf(a);
    if (bal == 0) return;
    shares = bound(shares, 1, bal);
    vm.prank(a);
    try vault.requestRedeem(shares, a, a) {} catch {}
  }

  function h_approveAndRedeem(uint256 actorSeed) external {
    address a = actors[actorSeed % 3];
    uint256 pending = vault.pendingRedeemShares(a);
    if (pending == 0 || !_navFresh()) return;
    vm.prank(manager);
    try vault.approveRedemption(a, pending) {} catch { return; }
    uint256 claimable = vault.maxRedeem(a);
    if (claimable == 0) return;
    vm.prank(a);
    try vault.redeem(claimable, a, a) {} catch {}
  }

  function h_cancelDeposit(uint256 actorSeed) external {
    address a = actors[actorSeed % 3];
    if (vault.pendingDepositAssets(a) == 0) return;
    vm.prank(a);
    try vault.cancelDepositRequest(a, a) {} catch {}
  }

  function h_pokeNav(uint256 batch) external {
    batch = bound(batch, 1, 20);
    mockCalculator.setNextValuation(DEFAULT_LOAN_VALUATION);
    vm.prank(manager);
    try vault.updateNav(batch) {} catch {}
  }

  function invariant_solvency() public view {
    uint256 backing = usdc.balanceOf(address(vault)) + DEFAULT_LOAN_VALUATION;
    uint256 obligations = vault.totalClaimableRedeemAssets() + vault.totalPendingDepositAssets();
    assertGe(backing + 1, obligations, "vault promete mas de lo que respalda");
  }

  function invariant_sharePriceStable() public view {
    if (shareToken.totalSupply() == 0) return;
    uint256 p = _sharePrice();
    uint256 diff = p > priceAtSetup ? p - priceAtSetup : priceAtSetup - p;
    assertLe(diff, priceAtSetup / 1000 + 2, "sharePrice se movio sin cambio de valuacion");
  }

  function _navFresh() internal view returns (bool) {
    return vault.lastNav() > 0;
  }
}
