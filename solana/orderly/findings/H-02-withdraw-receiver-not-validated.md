# [H-02] `oapp_lz_receive` no valida que la cuenta `user` corresponda al `receiver` del mensaje, permitiendo robar retiros ajenos

**Contest:** Orderly Network Solana Contract (Sherlock, público — shadow audit)
**Archivo:** `solana-vault/.../instructions/oapp_instr/oapp_lz_receive.rs`
**Severidad:** High
**Estado:** candidato (pendiente de validar contra el reporte público de Sherlock)

## Resumen

La instrucción `oapp_lz_receive` procesa mensajes de retiro provenientes de la cadena EVM y
transfiere USDC del vault a una cuenta `user` que **elige quien ejecuta la transacción** (el
`payer`), sin verificar que esa cuenta corresponda al `receiver` indicado dentro del mensaje
firmado. Un ejecutor malicioso puede desviar el retiro de cualquier usuario a una wallet
propia.

## Invariante / propiedad rota

El mensaje de retiro autentica *qué* se retira y *para quién* (`receiver`), pero el programa
no hace cumplir el *para quién*. Se rompe la correspondencia entre el beneficiario autorizado
en el mensaje y el destinatario real de los fondos.

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

El transfer envía los fondos a `user_deposit_wallet` (cuya autoridad es `user`):

\`\`\`rust
let cpi_accounts = Transfer {
    from: self.vault_deposit_wallet.to_account_info(),
    to: self.user_deposit_wallet.to_account_info(),
    authority: self.vault_authority.to_account_info(),
};
\`\`\`

El mensaje decodificado (`AccountWithdrawSol`) contiene un campo `receiver: [u8; 32]`, pero una
búsqueda en todo el programa muestra que `receiver` se usa **solo** para emitir el evento
`VaultWithdrawn`; nunca se compara contra `user`. No existe una constraint del tipo
`user.key().to_bytes() == withdraw_params.receiver`.

El `payer` que ejecuta la instrucción es un `Signer` sin restricción (cualquiera puede
ejecutarla, típicamente un relayer), y es quien provee las cuentas `user` / `user_deposit_wallet`.

## Camino de ataque

1. Alice solicita un retiro legítimo en Orderly (EVM). Se emite un mensaje LayerZero con
   `receiver = Alice`, autenticado por el `peer` correcto.
2. El mensaje llega a Solana. La constraint de `peer` (`peer.address == params.sender`) valida
   el origen: pasa, porque el mensaje es legítimo.
3. El ejecutor malicioso Bob arma la transacción `oapp_lz_receive` y pasa:
   - `user = Bob`
   - `user_deposit_wallet = ATA de Bob para el deposit_token`
4. Como nada ata `user` a `receiver`, el transfer envía el USDC de Alice a la ATA de Bob.
5. Bob cobra el retiro de Alice. Alice pierde sus fondos.

La protección de `order_delivery` / `inbound_nonce` no mitiga esto: controla el *orden* de los
mensajes, no *quién* recibe. El desvío funciona respetando el nonce.

## Impacto

Robo directo de fondos: cualquier retiro puede ser interceptado y redirigido por quien ejecute
la instrucción de entrega. Pérdida total de los montos en retiro.

## Mitigación recomendada

Atar `user` al `receiver` del mensaje. Como el binding depende del payload (no se conoce al
construir el struct de cuentas), validarlo dentro de `apply` tras decodificar:

\`\`\`rust
require!(
    ctx.accounts.user.key().to_bytes() == withdraw_params.receiver,
    OAppError::InvalidReceiver
);
\`\`\`

(o la conversión de formato que corresponda entre el `receiver` de 32 bytes y el Pubkey.)

## Notas de calibración (shadow audit)

- Verificar contra el reporte público de findings del contest: severidad asignada y número de
  duplicados.
- Clase: *missing account validation* — falta de binding entre un dato autenticado del payload
  (`receiver`) y la cuenta que efectivamente recibe los fondos.

---

## Hallazgo secundario relacionado (mismo archivo)

**[L/M] Resta sin protección `token_amount - fee` (línea ~117).** El perfil de compilación no
declara `overflow-checks = true`, por lo que en release el underflow hace *wrapping* en vez de
panic. Si el lado EVM pudiera emitir `fee > token_amount`, `amount_to_transfer` se volvería un
valor enorme y drenaría el vault; si no, el impacto se limita a los valores que el peer pueda
producir. Recomendación: `checked_sub` con error explícito, y/o activar `overflow-checks`.
Severidad sujeta a si el origen puede producir `fee > token_amount`.
