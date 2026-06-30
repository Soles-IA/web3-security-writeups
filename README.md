# Web3 Security Writeups

Smart contract security exercises, with each exploit written from scratch in Foundry.

The goal of this repository is not to collect solutions, but to document my own
reasoning when breaking contracts — the vulnerability class, how I spotted it,
the exploit, and the fix a protocol should apply.

I come from a hands-on DeFi background (deploying and debugging flash-loan and
lending strategies on Arbitrum) and I'm transitioning into security research.

## Methodology

1. **Read** the contract and trace every place a sensitive variable or privilege is modified.
2. **Hypothesize** the attack: what assumption can be broken from outside?
3. **Exploit** it with a Foundry test that proves the vulnerability runs.
4. **Fix** it: describe the correct design the protocol should have used.

## Exercises

| # | Exercise | Vulnerability class | Source | Writeup |
|---|----------|---------------------|--------|---------|
| 1 | Fallback | Weak access control | Ethernaut | [link](./ethernaut/01-Fallback.md) |
| 2 | Fallout | Unprotected initialization | Ethernaut | [link](./ethernaut/02-Fallout.md) |
| 3 | Reentrance | Reentrancy | Ethernaut | [link](./ethernaut/03-Reentrance.md) |
| 4 | Unstoppable | ERC4626 vault DoS | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/01-Unstoppable.md) |
| 5 | Naive Receiver | Flash-loan fee abuse + _msgSender spoofing | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/02-NaiveReceiver.md) |
| 6 | Truster | Arbitrary call / approve abuse | Damn Vulnerable DeFi | [link](./damn-vulnerable-defi/03-Truster.md) |

## Running the exploits

This is a Foundry project. The three Ethernaut exploits are runnable as tests:

```bash
git clone --recurse-submodules https://github.com/Soles-IA/web3-security-writeups.git
cd web3-security-writeups
forge test -vv
```

Each exploit is in `test/` and the vulnerable contract in `src/`. All three
Ethernaut exploits pass, demonstrating the vulnerability described in the
matching writeup. (The Unstoppable writeup is documented only; its exploit
lives in the separate Damn Vulnerable DeFi project.)

## Background

Before focusing on security I built and deployed contracts on Arbitrum mainnet
involving Balancer flash loans, Aave V3 (including eMode), and Uniswap V3 swaps.
Debugging real reverts by reading call traces is what pulled me toward
understanding *why* contracts fail — and from there, into security research.
