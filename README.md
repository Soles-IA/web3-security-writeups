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

| # | Exercise | Vulnerability class | Source |
|---|----------|---------------------|--------|
| 1 | Fallback | Weak access control | Ethernaut |
| 2 | Fallout | Unprotected initialization | Ethernaut |
| 3 | Reentrance | Reentrancy | Ethernaut |
| 4 | Unstoppable | ERC4626 vault DoS | Damn Vulnerable DeFi |
