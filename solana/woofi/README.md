# WOOFi Solana — Shadow Audit (en progreso)

> **Shadow audit** sobre un contest público de Sherlock ya cerrado. **No participé en el
> contest original.** Trabajo en progreso: análisis de revisión independiente sobre código
> público. Los candidatos aquí NO son findings confirmados hasta cerrar su verificación y
> calibrar contra el reporte oficial. El código auditado es propiedad de WOO Network y se
> referencia por enlace, no se redistribuye.

## Fuente

- **Contest (Sherlock):** [2024-08-woofi-solana-deployment](https://github.com/sherlock-audit/2024-08-woofi-solana-deployment)
- **Commit auditado:** `WOOFi_Solana @ c7835fbafdb3fe154b2365fea1969058caa9ee09`

## Qué hace el protocolo

DEX con market-making proactivo (PMM). Swaps entre SOL/USDT/USDC. El precio sale de un
oráculo (`Wooracle`) alimentado off-chain + Pyth, más una fórmula que mueve el precio con
cada trade (`post_price`). Dos programas en scope: `woofi` (core) y `rebate_manager`.

## Estado

| Área | Estado |
|------|--------|
| Binding de cuentas en `swap` | Revisado — bien defendido (muchos `has_one`/`constraint`) |
| Matemática de swap | Revisado — sólida (`checked_mul_div`, guards de gamma/notional) |
| Candidato: doble timestamp / staleness | ❌ Descartado con fundamento (ver WIP-notes) |
| Candidato: wooracle authority sin gate en init | 🔍 Abierto — pendiente `create_pool.rs` |
| Cobertura del scope | Parcial — falta barrer `rebate_manager/`, `woopool.rs`, etc. |

Detalle del análisis en [WIP-notes.md](WIP-notes.md).

## Nota metodológica

Este scope se aborda aplicando el [bug catalog](../bug-catalog.md). El binding de cuentas y la
matemática resultaron bien defendidos; el foco de riesgo está en oráculo/authority. El
candidato abierto (wooracle authority) matchea el patrón "PDA seeds without owner identity +
no authority gate on init" del catalog.
