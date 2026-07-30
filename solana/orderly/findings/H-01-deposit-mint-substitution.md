# [H-01] `deposit` no valida que el mint depositado corresponda al `token_hash`, permitiendo acreditar USDC en el Ledger EVM con tokens sin valor

**Contest:** Orderly Network Solana Contract (Sherlock, público — shadow audit)
**Archivo:** `solana-vault/.../instructions/vault_instr/deposit.rs`
**Severidad:** High
**Estado:** candidato (pendiente de validar contra el reporte público de Sherlock)

## Resumen

La instrucción `deposit` transfiere un mint (`deposit_token`) elegido por el usuario sin
verificar que coincida con el mint canónico registrado para el `token_hash` que se envía en
el mensaje cross-chain. Un atacante puede pasar el `token_hash` de un token permitido (USDC)
mientras deposita un token sin valor, provocando que el Ledger del lado EVM le acredite USDC
sin respaldo real en el vault de Solana.

## Invariante roto

El README del contest declara como invariante sagrado:

> The USDC balance of Vault program on Solana is no less than the Vault balance record on
> Ledger contract on Orderly chain.

Este finding rompe ese invariante directamente: se acredita balance en el Ledger EVM sin un
depósito de valor equivalente en Solana.

## Detalle de la causa raíz

En el struct de cuentas `Deposit`, la cuenta del mint no tiene ninguna restricción:

\`\`\`rust
#[account()]
pub deposit_token: Box<Account<'info, Mint>>,
\`\`\`

El `allowed_token` se deriva del `token_hash` provisto por el usuario y solo se usa para
comprobar el flag `allowed`:

\`\`\`rust
#[account(
    seeds = [TOKEN_SEED, deposit_params.token_hash.as_ref()],
    bump = allowed_token.bump,
    constraint = allowed_token.allowed == true @ VaultError::TokenNotAllowed
)]
pub allowed_token: Box<Account<'info, AllowedToken>>,
\`\`\`

El estado `AllowedToken` SÍ almacena el mint canónico (`mint_account: Pubkey`), grabado por el
admin en `set_token`:

\`\`\`rust
ctx.accounts.allowed_token.mint_account = params.mint_account;
\`\`\`

Pero `deposit` nunca compara `deposit_token.key()` contra `allowed_token.mint_account`. Las
ATAs de usuario y de vault están atadas a `deposit_token` (arbitrario), no al mint canónico.
El mensaje enviado al Ledger usa `deposit_params.token_hash`, no el mint real transferido.

Pista de confirmación: en `set_token.rs` los devs dejaron un resto comentado que muestra la
intención de atar el binding por mint y que quedó incompleta:

\`\`\`rust
seeds = [TOKEN_SEED, params.token_hash.as_ref()], // mint_account.key().as_ref(),
\`\`\`

## Camino de ataque (PoC conceptual)

1. El admin registra USDC de forma legítima: `token_hash_USDC -> mint_account = USDC, allowed = true`.
2. El atacante crea un mint propio sin valor y una ATA con saldo.
3. El atacante llama `deposit` con:
   - `deposit_params.token_hash = token_hash_USDC`  (pasa `allowed == true`)
   - `deposit_token = <mint basura del atacante>`   (pasa: `#[account()]` sin constraint)
   - `user_token_account` / `vault_token_account` = ATAs del mint basura (`init_if_needed` crea la del vault)
4. El `transfer` mueve tokens basura al vault; el mensaje LayerZero codifica `token_hash_USDC`.
5. El Ledger EVM acredita USDC al `account_id` del atacante.
6. El atacante retira USDC real del sistema contra un depósito sin valor. Invariante roto.

## Impacto

Pérdida directa de fondos: el atacante extrae USDC real del protocolo sin aportar valor
equivalente. No requiere condiciones especiales de mercado ni carreras contra bots.

## Mitigación recomendada

Atar el mint depositado al mint canónico del `token_hash` en el struct de cuentas:

\`\`\`rust
#[account(
    constraint = deposit_token.key() == allowed_token.mint_account @ VaultError::InvalidMint
)]
pub deposit_token: Box<Account<'info, Mint>>,
\`\`\`

(Alternativa: incluir `mint_account` en los seeds del PDA `allowed_token`, como sugiere el
comentario muerto en `set_token.rs`.)

## Notas de calibración (shadow audit)

- Verificar este candidato contra el reporte público de findings del contest en el repo de
  `sherlock-audit`. Registrar si fue reportado, con qué severidad, y si el duplicado fue
  numeroso (afecta el reward split).
- Clase de vulnerabilidad: *missing account / mint validation* (la clase #1 en auditoría de
  programas Solana).
