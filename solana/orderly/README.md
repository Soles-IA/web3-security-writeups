# Orderly Network Solana Contract — Shadow Audit

> **Shadow audit** sobre un contest público de Sherlock ya cerrado. **No participé en el
> contest original.** Este trabajo es un ejercicio de revisión independiente sobre código
> público, hecho para entrenar metodología y construir track record. Los findings acá
> reportados son mi propio análisis; el código auditado es propiedad de Orderly Network y se
> referencia por enlace, no se redistribuye en este repositorio.

## Fuente

- **Contest (Sherlock):** [2024-09-orderly-network-solana-contract](https://github.com/sherlock-audit/2024-09-orderly-network-solana-contract)
- **Commit auditado (Solana):** `solana-vault @ bd8b6dbeb3300319fd9dad262298ec0cd1152344`
- **Commit auditado (EVM connector):** `sol-cc @ dc99b068cda9a6067b35edf629acd1730e5982a3`

## Qué hace el protocolo

Orderly despliega un **vault en Solana** (programa Rust/Anchor) donde los usuarios depositan
USDC. Cada depósito se comunica a la **cadena de Orderly** (un L2 EVM sobre OP Stack) mediante
**LayerZero**, donde un contrato Ledger lleva el registro de balances. El componente `sol-cc`
(`SolConnector`) vive del lado EVM y recibe/envía los mensajes LayerZero.

Flujo resumido:

\`\`\`
Usuario --deposit(USDC)--> Vault (Solana)  --LayerZero msg--> Ledger (Orderly L2 EVM)
\`\`\`

## Invariante principal

Declarado por el protocolo en el README del contest:

> The USDC balance of the Vault program on Solana is no less than the Vault balance record on
> the Ledger contract on Orderly chain.

Todo lo que permita acreditar balance en el Ledger EVM sin un depósito de valor equivalente en
Solana (o retirar de Solana sin reflejarlo) rompe este invariante y es candidato a High.

## Scope (Rust / Solana — foco de esta revisión)

~2.264 LOC de Rust. Zonas de mayor superficie de ataque, priorizadas:

| Prioridad | Archivo | Por qué |
|-----------|---------|---------|
| Alta | \`vault_instr/deposit.rs\` | Entrada de fondos; toca el invariante directo |
| Alta | \`oapp_instr/oapp_lz_receive.rs\` + \`oapp_lz_receive_types.rs\` | Recepción de mensajes cross-chain; validación de cuentas |
| Media | \`state/\` + \`instructions/seeds.rs\` | Definición de PDAs y control de acceso |
| Media | \`vault_instr/set_*\`, \`oapp_instr/set_*\` | Superficie permisionada (admin) |

## Known issues (declarados aceptables — NO reportar)

- Front-running durante la inicialización de PDA.
- Mal comportamiento del sequencer del L2 (se asume que no ocurre).

## Findings

| ID | Título | Severidad | Estado |
|----|--------|-----------|--------|
| [H-01](findings/H-01-deposit-mint-substitution.md) | \`deposit\` no valida el mint contra el \`token_hash\` | High | Candidato |
| [H-02](findings/H-02-withdraw-receiver-not-validated.md) | `oapp_lz_receive` no valida `user` contra `receiver` | High | Candidato |

> **Estado "Candidato":** finding identificado por revisión de código con camino de ataque
> razonado, pendiente de (a) PoC ejecutable y (b) validación contra el reporte público de
> findings del contest. Se actualiza a *Confirmado* o se ajusta tras la calibración.

## Metodología

Revisión aplicando un proceso de 7 pasos: mapeo de scope y priorización, lectura del modelo de
confianza, análisis de la superficie untrusted, verificación de invariantes, construcción de
PoCs, redacción de findings, y calibración contra veredictos públicos.
