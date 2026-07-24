import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { PublicKey, Keypair, SystemProgram } from "@solana/web3.js";
import {
  TOKEN_2022_PROGRAM_ID, createMint, getOrCreateAssociatedTokenAccount,
  mintTo, getAccount,
} from "@solana/spl-token";
import { expect } from "chai";
import * as fs from "fs";

const IDL = JSON.parse(fs.readFileSync("./target/idl/stake_flow.json", "utf8"));
const TP = TOKEN_2022_PROGRAM_ID;

describe("PoC: insolvency via rebalance + withdraw with no backing invariant", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = new Program(IDL, provider);
  const admin = (provider.wallet as anchor.Wallet).payer;
  const conn = provider.connection;

  let stakeMint: PublicKey;
  let cfgPda: PublicKey, stxMint: PublicKey, stakeVault: PublicKey, reserveVault: PublicKey;

  const alice = Keypair.generate();
  const bob = Keypair.generate();
  const DEC = 6;
  const UNIT = 10 ** DEC;
  const STAKE = BigInt(1000 * UNIT);

  before(async () => {
    for (const kp of [alice, bob]) {
      const sig = await conn.requestAirdrop(kp.publicKey, 2 * anchor.web3.LAMPORTS_PER_SOL);
      await conn.confirmTransaction(sig, "confirmed");
    }
    stakeMint = await createMint(conn, admin, admin.publicKey, null, DEC, undefined, undefined, TP);
    [cfgPda] = PublicKey.findProgramAddressSync([Buffer.from("protocol_config")], program.programId);
    [stxMint] = PublicKey.findProgramAddressSync([Buffer.from("stx_mint")], program.programId);
    [stakeVault] = PublicKey.findProgramAddressSync([Buffer.from("stake_vault")], program.programId);
    [reserveVault] = PublicKey.findProgramAddressSync([Buffer.from("reserve_vault")], program.programId);
  });

  it("total_staked promises backing the vault does not hold: Alice cannot unstake", async () => {
    await program.methods
      .initialize(new anchor.BN(500), new anchor.BN(1000))
      .accounts({
        protocolConfig: cfgPda, stakeTokenMint: stakeMint, stxMint, stakeVault, reserveVault,
        admin: admin.publicKey, tokenProgram: TP, systemProgram: SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      }).rpc();

    const setup = async (kp: Keypair) => {
      const xata = await getOrCreateAssociatedTokenAccount(conn, admin, stakeMint, kp.publicKey, false, undefined, undefined, TP);
      await mintTo(conn, admin, stakeMint, xata.address, admin, STAKE, [], undefined, TP);
      const stxata = await getOrCreateAssociatedTokenAccount(conn, admin, stxMint, kp.publicKey, false, undefined, undefined, TP);
      return { x: xata.address, stx: stxata.address };
    };
    const A = await setup(alice);
    const B = await setup(bob);

    const stakeLiquid = async (kp: Keypair, accts: any, amount: bigint) =>
      program.methods.stakeLiquid(new anchor.BN(amount.toString()))
        .accounts({
          protocolConfig: cfgPda, stxMint, stakeTokenMint: stakeMint, stakeVault,
          userTokenAccount: accts.x, userStxAccount: accts.stx, user: kp.publicKey, tokenProgram: TP,
        }).signers([kp]).rpc();

    await stakeLiquid(alice, A, STAKE);
    await stakeLiquid(bob, B, STAKE);

    let vault = await getAccount(conn, stakeVault, undefined, TP);
    let cfg = await program.account.protocolConfig.fetch(cfgPda);
    console.log("after stakes   -> total_staked:", cfg.totalStaked.toString(), " vault:", vault.amount.toString());

    // liquidity manager moves 1500 from stake vault to reserve
    const REB = BigInt(1500 * UNIT);
    await program.methods.rebalancePools(new anchor.BN(REB.toString()), true)
      .accounts({
        protocolConfig: cfgPda, stakeTokenMint: stakeMint, stakeVault, reserveVault,
        liquidityManager: admin.publicKey, tokenProgram: TP,
      }).rpc();

    // and withdraws them out of the protocol (yield farming)
    const mgrAta = await getOrCreateAssociatedTokenAccount(conn, admin, stakeMint, admin.publicKey, false, undefined, undefined, TP);
    await program.methods.withdrawReserves(new anchor.BN(REB.toString()))
      .accounts({
        protocolConfig: cfgPda, stakeTokenMint: stakeMint, reserveVault,
        managerTokenAccount: mgrAta.address, liquidityManager: admin.publicKey, tokenProgram: TP,
      }).rpc();

    vault = await getAccount(conn, stakeVault, undefined, TP);
    cfg = await program.account.protocolConfig.fetch(cfgPda);
    console.log("after drainage -> total_staked:", cfg.totalStaked.toString(), " vault:", vault.amount.toString());
    expect(Number(vault.amount)).to.be.lessThan(Number(cfg.totalStaked.toString()));

    // Alice's stX are priced off total_staked, but the vault cannot pay
    let reverted = false;
    try {
      await program.methods.unstakeLiquid(new anchor.BN(STAKE.toString()))
        .accounts({
          protocolConfig: cfgPda, stxMint, stakeTokenMint: stakeMint, stakeVault,
          userTokenAccount: A.x, userStxAccount: A.stx, user: alice.publicKey, tokenProgram: TP,
        }).signers([alice]).rpc();
    } catch (e: any) {
      reverted = true;
      console.log("Alice's unstake REVERTED:", (e.error?.errorCode?.code) || "InsufficientVaultBalance");
    }
    expect(reverted).to.equal(true);
  });
});
