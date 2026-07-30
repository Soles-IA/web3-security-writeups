# Orderly Network Solana Contract — Shadow Audit

> **Shadow audit** sobre un contest público de Sherlock ya cerrado. **No participé en el
> contest original.** Ejercicio de revisión independiente sobre código público. Los findings
> son mi propio análisis; el código auditado es propiedad de Orderly Network y se referencia
> por enlace, no se redistribuye.

**Resultado:** identifiqué de forma independiente **dos vulnerabilidades High** que coinciden
con issues **validados por el sponsor** en el reporte oficial de Sherlock — sustitución de mint
en `deposit` ([issue #37](https://github.com/sherlock-audit/2024-09-orderly-network-solana-contract-judging/issues/37))
y `receiver` no validado en el retiro (fix oficial en
[PR #4](https://github.com/OrderlyNetwork/solana-vault/pull/4/commits/a9f56db5e63562df9eb6a39803f3df12b7959032)).

## Fuente

- **Contest (Sherlock):** [2024-09-orderly-network-solana-contract](https://github.com/sherlock-audit/2024-09-orderly-network-solana-contract)
- **Judging repo:** [2024-09-orderly-network-solana-contract-judging](https://github.com/sherlock-audit/2024-09-orderly-network-solana-contract-judging)
- **Commit auditado (Solana):** `solana-vault @ bd8b6dbeb3300319fd9dad262298ec0cd1152344`

## Qué hace el protocolo

Vault en Solana (Rust/Anchor) donde los usuarios depositan USDC. Cada depósito se comunica a la
cadena de Orderly (L2 EVM sobre OP Stack) vía LayerZero, donde un contrato Ledger lleva el
registro de balances.

\`\`\`
Usuario --deposit(USDC)--> Vault (Solana)  --LayerZero msg--> Ledger (Orderly L2 EVM)
\`\`\`

## Invariante principal

> The USDC balance of the Vault program on Solana is no less than the Vault balance record on
> the Ledger contract on Orderly chain.

## Findings

| ID | Título | Severidad | Estado |
|----|--------|-----------|--------|
| [H-01](findings/H-01-deposit-mint-substitution.md) | `deposit` no valida el mint contra el `token_hash` | High | ✅ Confirmado (issue #37, Sponsor Confirmed) |
| [H-02](findings/H-02-withdraw-receiver-not-validated.md) | `oapp_lz_receive` no valida `user` contra `receiver` | High | ✅ Confirmado (Sponsor Confirmed, fix PR #4) |

## Known issues (declarados aceptables — NO reportar)

- Front-running durante la inicialización de PDA.
- Mal comportamiento del sequencer del L2.

## Metodología

Proceso de 7 pasos: mapeo de scope y priorización, lectura del modelo de confianza, análisis de
la superficie untrusted, verificación de invariantes, construcción de PoCs, redacción de
findings, y calibración contra veredictos públicos.
