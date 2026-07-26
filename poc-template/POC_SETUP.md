# Anchor PoC template — working setup

Verified working: Anchor 0.31.1, Solana release 4.1.1 (platform-tools v1.54,
Cargo 1.89), Node 20, Rust 1.97 (system). Test passes end to end.

## The root problem (edition2024 cascade)

`anchor build` fails with "feature edition2024 is required ... not stabilized in
Cargo 1.79/1.84". Cause: the rustup `solana` toolchain and Anchor's default
platform-tools ship an old Cargo that can't parse modern deps (hashbrown, blake3,
cpufeatures, borsh...). edition2024 stabilized in Cargo 1.85. Chasing individual
dep downgrades never ends — fix the toolchain instead.

## The fix (in order)

1. Session prep (each new shell):
   source ~/.nvm/nvm.sh && nvm use 20
   sudo swapon /swapfile 2>/dev/null   # ignore "unable to resolve host"

2. Make release 4.1.1 active (it ships Cargo 1.89 + target sbpf-solana-solana):
   ln -sfn ~/.local/share/solana/install/releases/4.1.1/solana-release \
     ~/.local/share/solana/install/active_release
   cargo-build-sbf --version   # must show platform-tools v1.54, rustc 1.89.0

3. Do NOT set solana_version in Anchor.toml — it makes Anchor re-link the
   `solana` rustup toolchain to an old Cargo on every build.

4. Build the program with cargo-build-sbf directly (NOT `anchor build`, whose
   toolchain management re-links to the old Cargo):
   cd programs/<name>
   ~/.local/share/solana/install/releases/4.1.1/solana-release/bin/cargo-build-sbf

5. Generate the IDL to disk (anchor idl build prints to stdout; redirect it):
   cd <project-root>
   mkdir -p target/idl
   anchor idl build > target/idl/<name>.json
   # verify it's non-empty: ls -la target/idl/

6. Run the test against the prebuilt .so + IDL (skip Anchor's build):
   anchor test --skip-build

## To use for a contest PoC

1. Copy this folder.
2. Replace programs/<name>/src/lib.rs with the target program.
3. Write the exploit in tests/<name>.ts.
4. Steps 4-6 above.
