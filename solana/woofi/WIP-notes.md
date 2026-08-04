# WOOFi Solana — Shadow Audit (WIP)

> Estado: en progreso. Notas de sesión para retomar. NO son findings confirmados.
> Contest: Sherlock, `2024-08-woofi-solana-deployment`.
> Commit: `WOOFi_Solana @ c7835fbafdb3fe154b2365fea1969058caa9ee09`.

## Qué es el protocolo

DEX con market-making proactivo (PMM). Swaps SOL/USDT/USDC. El precio sale de un
oráculo (`Wooracle`) alimentado off-chain + Pyth, más una fórmula que mueve el precio
con cada trade (`post_price`). Dos programas en scope: `woofi` (core) y `rebate_manager`.

## Cobertura hasta ahora

Leídos: `swap.rs`, `swap_math.rs`, `wooracle.rs`, `get_price.rs`, `math.rs`,
`decimals.rs`, `create_wooracle.rs`, `set_woo_state.rs`.
Pendientes (barrido no completo — aplicar leccion de coverage): `create_pool.rs`,
`woopool.rs`, `wooconfig.rs`, todo `rebate_manager/`, `claim_fee.rs`,
`deposit_withdraw.rs`, `query.rs`, `token.rs`, resto de admin/.

## Observacion general

La validacion de cuentas del `swap` es RIGUROSA (muchos `has_one`/`constraint` atando
wooracle<->woopool<->price_update<->vault). A diferencia de Orderly, el binding de cuentas
esta bien defendido aqui. La matematica usa `checked_mul_div` en todos lados, con guards
(`max_notional_swap`, `max_gamma`, `feasible_out`, `price_out > 0`). El riesgo, si existe,
esta en oraculo/authority, no en binding de cuentas ni en overflow.

## Candidato DESCARTADO — doble timestamp / staleness burlable

Hipotesis: `wo_feasible = now <= updated_at + stale_duration`, y `updated_at` lo refresca
cada swap via `post_price`->`update_now`. Se puede mantener el oraculo "fresco" con swaps
mientras el precio real esta viejo?

Descarte fundamentado: el precio solo se acepta si pasan DOS condiciones a la vez —
`wo_feasible` Y `wo_price_in_bound`. La segunda exige que `wo_price` este dentro de `bound`
del `clo_price`, y `clo_price` se calcula desde `pyth_result` via
`get_price_no_older_than(&Clock, maximum_age, feed)`, que REVIERTE la tx si Pyth esta mas
viejo que `maximum_age`. Si Pyth esta stale -> no hay swap. Si Pyth esta fresco -> el bound
ancla al precio real. Refrescar `updated_at` con swaps no compra nada. Los dos relojes no
dejan hueco. No explotable desde el programa.

## Candidato ABIERTO (prioridad para retomar) — wooracle authority sin gate en init

En `create_wooracle.rs`:
- La cuenta `admin` es `Signer` SIN constraint que lo ate a un admin legitimo del `wooconfig`.
- El handler hace `wooracle.authority = admin.key()` — quien crea el oraculo se autoasigna
  como authority.
- El `wooconfig` se pasa pero NO se valida que el signer este en su lista de admins.

Matchea el patron del catalog: "PDA seeds without owner identity + no authority gate on init
— first caller seizes it". Primo del WOOFi Medium ya conocido (rebate manager), aplicado al
WOORACLE.

Si un atacante crea un wooracle y se pone como authority, puede llamar los `set_*` handlers
(`set_price_handler`, `set_state_handler`, etc.) que validan `wooracle.authority == authority`,
y setear un PRECIO ARBITRARIO. Si el swap puede usar ese wooracle malicioso -> manipulacion
total de precio -> drenaje.

### Que falta para confirmar o descartar
1. Los seeds del wooracle incluyen `feed_account` y `price_update`, asi que el PDA depende de
   esos. Ver si eso limita al atacante.
2. El swap ata `woopool_from.wooracle` (via `address = woopool_from.wooracle`). El vector real
   depende de si un atacante puede hacer que un `woopool` en uso apunte a SU wooracle malicioso.
   -> LEER `create_pool.rs`: como se ata pool<->wooracle? hay gate de authority en create_pool?
3. Si el pool legitimo ya apunta a un wooracle legitimo y no se puede repuntar, el vector se
   reduce a "crear pool+wooracle propios", que quiza no toca fondos de otros -> severidad menor.
   Si se puede inyectar el wooracle malicioso en un flujo que otros usan -> High.

### Calibracion pendiente
Comparar contra findings publicos del contest (watson "g" tiene 3 findings en WOOFi Solana,
incluyendo "attacker can control rebate managers... only 1 per quote token"). Ver si el
wooracle-authority esta reportado y con que severidad.

## FINDING (High) — rebate_manager: front-running de create -> robo de fees

**Archivos:** rebate_manager/create_rebate_manager.rs, deposit_withdraw.rs, state/rebate_manager.rs
**Severidad:** High
**Estado:** confirmado por lectura; coincide con finding publico del watson "g".

### Causa raiz
create_rebate_manager: `authority` es Signer SIN constraint; seeds del PDA =
[REBATEMANAGER_SEED, quote_token_mint] (solo el mint, sin identidad del creador ->
1 rebate manager por quote token); el handler hace initialize(authority) -> el
creador se autoasigna authority. Como es `init`, el primero que lo crea lo controla
permanentemente.

### Impacto (High)
withdraw (deposit_withdraw.rs): constraint = rebate_manager.authority == authority
|| admin_authority.contains(authority), y transfiere del token_vault a la wallet del
authority. -> El atacante que hace front-run de create se vuelve authority y VACIA
todas las rebate fees depositadas.

### Cadena de ataque
1. Atacante crea el rebate manager de USDC antes que WOOFi, se pone authority.
2. `init` impide recrearlo -> control permanente.
3. WOOFi deposita fees en ese vault.
4. Atacante llama withdraw -> roba las fees.

### Contraste con el candidato wooracle (descartado)
Mismo patron "create sin gate + self-assign authority". En wooracle, create_pool lo
contenia con has_one=authority (sin impacto). Aqui NADA lo contiene. La diferencia
esta en la validacion aguas abajo. LECCION: seguir la cadena completa.

### Fix
Atar create_rebate_manager a un admin global, o incluir la identidad del admin en los
seeds del PDA.
