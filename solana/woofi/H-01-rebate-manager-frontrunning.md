# WOOFi Solana — Shadow Audit

> **Shadow audit** sobre un contest publico de Sherlock ya cerrado. **No participe en el
> contest original.** Revision independiente sobre codigo publico, para entrenar metodologia
> y construir track record. El finding se calibra contra el reporte publico del contest. El
> codigo auditado es propiedad de WOO Network y se referencia por enlace, no se redistribuye.

## Resultado

Identifique de forma independiente un **High** en el programa `rebate_manager` —control del
rebate manager por front-running de su creacion— que **coincide con un finding validado** del
Lead Senior Watson del contest ([g / gjaldon](https://audits.sherlock.xyz/watson/g)):
*"Attacker can control rebate managers for supported tokens since there is only 1 rebate
manager per quote token."*

Ademas, la revision descarto con fundamento tres candidatos, documentando por que no son
findings — incluido uno (wooracle-authority) que exhibe el **mismo patron** que el High pero
sin impacto, por una defensa aguas abajo. Ese contraste es la leccion central del audit.

## Fuente

- **Contest (Sherlock, Sep 2024, $23.6K):** [2024-08-woofi-solana-deployment](https://github.com/sherlock-audit/2024-08-woofi-solana-deployment)
- **Watson de referencia:** g / gjaldon (Lead Senior Watson del contest)

## Que hace el protocolo

WOOFi es un DEX con market-making proactivo (sPMM). El programa `woofi` maneja swaps y precios
(oraculo Wooracle + Pyth); el programa `rebate_manager` gestiona los reembolsos de fees a
brokers, con un vault de tokens por cada quote token soportado (USDC, USDT...).

---

## [H-01] Front-running de `create_rebate_manager` permite apropiarse del rebate manager y robar las fees

**Severidad:** High
**Archivos:** `rebate_manager/src/instructions/admin/create_rebate_manager.rs`,
`rebate_manager/src/instructions/admin/deposit_withdraw.rs`,
`rebate_manager/src/state/rebate_manager.rs`
**Calibracion:** coincide con el finding validado de *g* ("only 1 rebate manager per quote token").

### Causa raiz

`create_rebate_manager` no restringe quien puede crearlo, y el creador se autoasigna como
authority:

- `authority` es un `Signer` sin constraint que lo ate a un admin legitimo.
- el PDA usa seeds `[REBATEMANAGER_SEED, quote_token_mint]` — solo el mint, sin identidad del
  creador.
- el handler hace `rebate_manager.initialize(authority, ...)`, grabando al firmante como authority.

Existe exactamente **un** rebate manager posible por quote token, y como es `init`, no se puede
recrear: el primero que lo cree para un token (p. ej. USDC) lo controla permanentemente.

### Impacto

`withdraw` (en `deposit_withdraw.rs`) autoriza al `authority` a vaciar el vault:

    constraint = rebate_manager.authority == authority.key()
              || rebate_manager.admin_authority.contains(authority.key)

y hace `transfer_from_vault_to_owner(...)` hacia la wallet del authority. Un atacante que hace
front-run de la creacion se convierte en `authority` y puede **retirar todas las rebate fees**
que el sistema deposite en ese vault. Robo directo de fondos.

### Camino de ataque

1. El atacante llama `create_rebate_manager` para USDC **antes** que el equipo de WOOFi, y se
   autoasigna como `authority`.
2. Como es `init` con seed solo del mint, nadie mas puede crear el de USDC -> control permanente.
3. WOOFi deposita las rebate fees en ese vault, creyendolo legitimo.
4. El atacante llama `withdraw` y vacia las fees hacia su wallet.

### Mitigacion

Atar `create_rebate_manager` a un admin global del sistema (validar el `Signer` contra un
`wooconfig`/lista de admins autorizada), o incluir la identidad del admin legitimo en los seeds
del PDA para que el atacante no pueda apropiarse del manager canonico.

---

## Candidatos descartados (con fundamento)

**Doble timestamp / staleness burlable (`get_price`) — descartado.** El precio solo se acepta
si pasan `wo_feasible` (timestamp interno, refrescable por swaps) **y** `wo_price_in_bound`
(dentro de un bound del precio de Pyth via `get_price_no_older_than`, que revierte si Pyth esta
stale). Los dos relojes no dejan ventana explotable.

**`deposit_token` sin constraint en el retiro — descartado.** En el path de retiro el transfer
va del vault al usuario y ambas ATAs cuelgan del mismo `deposit_token`; un mint basura tendria
vault vacio, sin valor que extraer.

**wooracle-authority sin gate en `create_wooracle` — descartado, y es la leccion central.**
`create_wooracle` exhibe el **mismo patron** que el H-01 (create sin gate + self-assign de
authority). Pero `create_pool` contiene el vector con `has_one = authority` sobre la cuenta
`wooracle`: un atacante solo puede usar su wooracle malicioso en un pool **donde el mismo es el
authority** (un pool propio y aislado), sin victimas.

### Leccion

El mismo patron sospechoso —create sin gate + self-assign de authority— aparecio **dos veces**
en WOOFi. En el wooracle es inofensivo porque `create_pool` lo contiene aguas abajo; en el
rebate_manager es un High porque `withdraw` confia en el authority sin mas validacion. **El
finding no es el patron: es el patron sin defensa en la cadena de uso.** Hay que seguir la
cadena completa (del `create` al `withdraw`) antes de decidir si algo es un finding o ruido.
