# Web3 Security Writeups

Smart contract security exercises, with each exploit written from scratch in [Foundry](https://book.getfoundry.sh/).

The goal of this repository is not to collect solutions, but to document my own
reasoning when breaking contracts — the vulnerability class, how I spotted it,
the exploit, and the fix a protocol should apply.

I come from a hands-on DeFi background (deploying and debugging flash-loan and
lending strategies on Arbitrum) and I'm transitioning into security research.
Writing each proof-of-concept myself, rather than reading a solution, is how I
make each vulnerability class stick.

## Methodology

For every exercise I follow the same loop, the way an auditor would:

1. **Read** the contract and trace every place a sensitive variable or privilege is modified.
2. **Hypothesize** the attack: what assumption can be broken from outside?
3. **Exploit** it with a Foundry test that proves the vulnerability runs.
4. **Fix** it: describe the correct design the protocol should have used.

## Exercises

| # | Exercise | Vulnerability class | Source |
|---|----------|---------------------|--------|
| 1 | [Fallback](./ethernaut/01-Fallback.md) | Weak access control (side-door to ownership) | Ethernaut |
| 2 | [Fallout](./ethernaut/02-Fallout.md) | Unprotected initialization (constructor typo) | Ethernaut |
| 3 | [Reentrance](./ethernaut/03-Reentrance.md) | Reentrancy (Checks-Effects-Interactions) | Ethernaut |
| 4 | [Unstoppable](./damn-vulnerable-defi/01-Unstoppable.md) | ERC4626 vault DoS via forced token donation | Damn Vulnerable DeFi |

## Tooling

- **Foundry** (`forge`) for writing and running exploits as Solidity tests
- **Tenderly / Phalcon** for transaction tracing (from prior DeFi work on Arbitrum)

## Background

Before focusing on security I built and deployed contracts on Arbitrum mainnet
involving Balancer flash loans, Aave V3 (including eMode), and Uniswap V3 swaps.
Debugging real reverts by reading call traces is what pulled me toward
understanding *why* contracts fail — and from there, into security research.

---

*This is a learning repository. Writeups are documented as I progress.*
