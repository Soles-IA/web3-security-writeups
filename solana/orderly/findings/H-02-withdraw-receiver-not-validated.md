# [H-02] `oapp_lz_receive` no valida que la cuenta `user` corresponda al `receiver` del mensaje, permitiendo robar retiros ajenos

**Contest:** Orderly Network Solana Contract (Sherlock, público — shadow audit)
**Archivo:** `solana-vault/.../instructions/oapp_instr/oapp_lz_receive.rs`
**Severidad:** High
**Estado:** ✅ Confirmado — calibrado contra el reporte oficial de Sherlock

## Resultado de calibración

Coincide con el issue validado de "withdrawal receiver not validated" del contest, etiquetado
**Sponsor Confirmed / Acknowledged**. El equipo del protocolo aplicó el fix en
[OrderlyNetwork/solana-vault PR #4](https://github.com/OrderlyNetwork/solana-vault/pull/4/commits/a9f56db5e63562df9eb6a39803f3df12b7959032):
se agregó a `oapp_lz_receive()` una verificación de que el destinatario del retiro sea el
`receiver` especificado en el payload — idéntico al fix que propuse.

> **Issue de judging: [#146](https://github.com/sherlock-audit/2024-09-orderly-network-solana-contract-judging/issues/146)** (Sponsor Acknowledged). Antes decía: completar desde el repo
> `2024-09-orderly-network-solana-contract-judging`.

Nota de calibración: otro watson (y4y, [issue #142](https://github.com/sherlock-audit/2024-09-orderly-network-solana-contract-judging/issues/142))
atacó el mismo archivo desde un ángulo más amplio ("falta control de acceso genérico") y quedó
**Sponsor Disputed**. Mi framing apuntó al vector específico y correcto (binding
`user`↔`receiver`), que es el que resultó válido.

## Resumen

La instrucción `oapp_lz_receive` procesa mensajes de retiro provenientes de la cadena EVM y
transfiere USDC del vault a una cuenta `user` que **elige quien ejecuta la transacción** (el
`payer`), sin verificar que esa cuenta corresponda al `receiver` indicado dentro del mensaje
firmado. Un ejecutor malicioso puede desviar el retiro de cualquier usuario a una wallet
propia.

## Causa raíz

La cuenta `user` no tiene ninguna restricción:

\`\`\`rust
/// CHECK
#[account()]
pub user: AccountInfo<'info>,

#[account(
    mut,
    associated_token::mint = deposit_token,
    associated_token::authority = user
)]
pub user_deposit_wallet: Account<'info, TokenAccount>,
\`\`\`

El transfer envía los fondos a `user_deposit_wallet` (cuya autoridad es `user`). El mensaje
decodificado contiene un campo `receiver: [u8; 32]`, pero una búsqueda en todo el programa
muestra que `receiver` se usa **solo** para emitir el evento `VaultWithdrawn`; nunca se compara
contra `user`. El `payer` que ejecuta es un `Signer` sin restricción (cualquiera puede
ejecutar), y provee las cuentas `user` / `user_deposit_wallet`.

## Camino de ataque

1. Alice solicita un retiro legítimo en Orderly (EVM). Se emite un mensaje LayerZero con
   `receiver = Alice`, autenticado por el `peer` correcto.
2. El mensaje llega a Solana. La constraint de `peer` valida el origen: pasa.
3. El ejecutor malicioso Bob arma la transacción y pasa `user = Bob` + su ATA.
4. Como nada ata `user` a `receiver`, el transfer envía el USDC de Alice a la ATA de Bob.
5. Bob cobra el retiro de Alice. Alice pierde sus fondos.

La protección de `order_delivery` / `inbound_nonce` no mitiga esto: controla el *orden* de los
mensajes, no *quién* recibe.

## Impacto

Robo directo de fondos: cualquier retiro puede ser interceptado y redirigido por quien ejecute
la instrucción de entrega.

## Mitigación recomendada

Atar `user` al `receiver` del mensaje, validándolo dentro de `apply` tras decodificar:

\`\`\`rust
require!(
    ctx.accounts.user.key().to_bytes() == withdraw_params.receiver,
    OAppError::InvalidReceiver
);
\`\`\`

## Clase de vulnerabilidad

*Missing account validation* — falta de binding entre un dato autenticado del payload
(`receiver`) y la cuenta que efectivamente recibe los fondos.

---

## Hallazgo secundario relacionado (mismo archivo)

**[L/M] Resta sin protección `token_amount - fee` (línea ~117).** El perfil de compilación no
declara `overflow-checks = true`, por lo que en release el underflow hace *wrapping* en vez de
panic. Recomendación: `checked_sub` con error explícito y/o activar `overflow-checks`.

---

## Candidatos evaluados y descartados (mismo archivo)

Al leer `oapp_lz_receive` marqué dos candidatos adicionales; tras verificarlos, ninguno es un
finding independiente. Se documentan porque descartar bien es parte del trabajo.

**`deposit_token` sin constraint (línea ~56) — DESCARTADO.** Igual que en el deposit, el
`deposit_token` del retiro no está atado a un mint canónico. Pero en el path de retiro el
transfer va *del vault al usuario*, y ambas ATAs cuelgan del mismo `deposit_token`. Si el
atacante pasara un mint basura, la ATA del vault para ese mint estaría vacía: no hay USDC real
que extraer por esa vía. El vector de valor real de este archivo es el binding `user`↔`receiver`
(H-02), no el mint. No constituye un finding separado.

**`.unwrap()` en el decode del mensaje (líneas ~108, ~111) — DESCARTADO (informational).**
`LzMessage::decode(...).unwrap()` y `AccountWithdrawSol::decode_packed(...).unwrap()` hacen panic
ante un payload malformado. Pero el mensaje ya pasó la constraint `peer.address == params.sender`
antes del decode, de modo que solo un peer legítimo (el EVM de Orderly) puede alcanzar esta ruta.
Un mensaje malformado exigiría que el peer confiable enviara basura, fuera del modelo de amenaza.
Es una nota de robustez (preferir manejo de error a panic), no una vulnerabilidad. Confirmado
indirectamente por la calibración: ningún issue validado del reporte apunta a estos `.unwrap()`.
