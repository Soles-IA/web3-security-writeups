# Solana / Anchor Audit Checklist

A personal catalog of bug classes seen across real contests (StakeFlow, MissionX,
Pump Science, WOOFi, Orderly), with the detection signal for each. Built to be
read at the start of every contest: for each instruction, walk this list.

## Sweep order (execute this on every instruction, under the clock)

Day one: list EVERY file and EVERY instruction in scope first. Then for each
instruction, in this order:

1. List every account it receives. For each: **"what binds this to being the
   correct one?"** Nothing / a caller-controlled param → candidate (see Account
   validation).
2. Trace the money: which accounts move funds, and does every path consult the
   shared accounting variable? (see State & accounting)
3. Check every `+ - *` on untrusted values for silent overflow; every `div` for
   who gets the remainder. (see Runtime specifics + Truncation)
4. Identify who can call it: is the `Signer`/`payer` tied to the legitimate role
   or endpoint? Is the check about ORIGIN or about the specific missing gate?
5. Two-filter triage the candidate (who triggers it / is it a known issue).

The first pass is breadth (every file read once); depth comes after. Both Pump
Science Highs and 3 of 4 WOOFi findings were in files never opened on a first pass.

## The one rule that finds most Solana bugs

**For every instruction, list every account it receives, and ask: "what binds
this to being the correct one?"** If the answer is "nothing" or "a parameter the
caller controls," that's the bug. Most paying Solana findings are account-validation
bugs, not math bugs.

## Account validation (the majority of paying findings)

**Account passed as parameter, not validated against source of truth.** An
instruction takes a mint / token account / config as a parameter but no Anchor
`constraint` ties it to the expected value. *Orderly #37:* `deposit` didn't check
`deposit_token == allowed_token.mint_account`; attacker deposited a dummy token
and got credited USDC. Signal: any account param without a `constraint =` or
`has_one` binding it. Fix is usually one constraint line.

**PDA signer seeds missing the bump.** A CPI signs with seeds that don't end in
`&[bump]`, or the PDA struct doesn't even store its bump. Derivation won't match
the real PDA and `invoke_signed` reverts every time — funds stranded. *WOOFi High:*
`seeds()` returned `[&[u8]; 2]`, no bump. Signal: any `new_with_signer` whose seeds
don't end in the bump; any PDA state struct with no `bump` field.

**PDA seeds without the owner identity + no authority gate on init.** A PDA is
derived from `[SEED, token_mint]` with no creator identity, `init` allows one per
key, and the `Signer` isn't checked against an admin. First caller seizes it.
*WOOFi Medium:* anyone could create a token's rebate manager and set themselves as
authority. Signal: `init` whose seeds omit the creator/admin and whose `Signer`
isn't validated. NOTE: some teams declare init front-running "known & acceptable"
(Orderly did) — always check known issues first.

**Shared signing authority + no beneficiary identity check.** A vault authority
PDA is shared across all users, and the code verifies the *message* is valid but
not that the *recipient* belongs to the user the message was for. *Orderly #146:*
User A front-runs User B's valid withdrawal and receives B's funds. Signal: any auth
that checks "message is legitimate" but not "the one being paid owns the message."
(EVM-catalog cousin: MyCut/MissionX "validate the slot but not the identity.")

**Missing access control on an external-integration entrypoint.** The entrypoint
a bridge/oracle (LayerZero, Wormhole, Pyth) calls has a gap on who can invoke it —
but frame the EXACT gap, not the approximate one. *Orderly:* two watsons hit
`oapp_lz_receive` from different angles. #142 framed it as "generic missing access
control" (anyone can call apply) — Sponsor DISPUTED it, because the `peer` constraint
DID validate message origin. The VALID finding (#146) was the specific binding gap:
`user` not tied to the payload `receiver`, so a caller could redirect someone else's
withdrawal. Lesson: the exact vector wins; the approximate one gets disputed. Signal:
don't stop at "is this callable by anyone?" — ask "what specific check is missing?"
The `peer` gate may cover origin while a per-beneficiary binding is still absent.

## State & accounting

**Field arrives as a parameter and never reaches state.** An instruction receives
a value, acts on it, but never writes it to the account. *Rust Fund:* `contribute`
never wrote `contribution.amount`. *Pump Science H-02:* `migration_token_allocation`
never written in `update_settings`. *StakeFlow F-03:* `deposit_yield` didn't update
`total_staked`. Mechanical check: count fields in, count fields written, compare.
(My historical blind spot — check it every time.)

**Two paths to the money, one ignores the shared counter.** Two exits move funds
but only one consults the accounting variable. *StakeFlow F-01:* `unstake_locked`
paid rewards without reading `reward_debt`. Signal: any counter (`reward_debt`,
`total_staked`, `reserve`) read on one path but not another that touches the same
funds.

**Truncation that favors the user, in a repeatable op.** Integer division whose
remainder falls to the user, repeated to drain. *StakeFlow F-02.* Rule: at every
`div`, ask who gets the remainder. All rounding must favor the protocol. (WOOFi did
this right — every `checked_mul_div` truncates down, fee rounds up.)

**Counter vs real vault balance desync.** A `reserve` field in state vs the real
`token_account.amount`. If they can diverge, price or solvency lies. *StakeFlow
insolvency* (though that one was trust-gated). WOOFi did it right: every exit checks
`reserve >= X && vault.amount >= X`.

## Solana runtime specifics (invisible to EVM auditors)

**Overflow is silent in release.** Unlike Solidity 0.8 (reverts by default), Rust
in release wraps. Look for raw `+`/`-`/`*` on values an untrusted party can push to
the type's limit. (Inverse lesson: in Solidity, don't waste time hunting overflow —
the compiler catches it.) *Orderly:* `token_amount - fee` with no `checked_sub` and
no `overflow-checks` in the release profile.

**Frozen token account can revert a transfer.** USDC's freeze authority (Circle)
can freeze an ATA; the Token Program reverts transfers to/from frozen accounts.

**External failure inside a nonce-ordered queue → total DoS.** If messages process
strictly by nonce and one reverts (e.g. transfer to a frozen ATA), the nonce never
increments and every later message is permanently blocked. *Orderly #70:* attacker
withdraws to a Circle-blacklisted account and bricks the queue. Signal: any
ordered-by-nonce loop where one reverting element halts progress. NOTE: a nonce that
gives ordering does NOT necessarily prevent redirection — in Orderly the
`inbound_nonce` ordered messages but did not stop the #146 beneficiary swap.

## Anchor covers these for free (don't spend time here)

Signer checks, owner checks, basic PDA derivation, type confusion — all handled by
Anchor constraints. The paying findings are business logic + the account-validation
gaps above that Anchor does NOT enforce.

## Two-filter triage on every candidate

1. **Who triggers it?** Trusted role (servicer/admin/manager/authority) → out of
   scope, drop it before building the mechanism.
2. **Is it in known issues?** Read SECURITY.md / the README's known-issues first.
   Same bug class can be valid in one contest and declared-known in another.

If unsure whether it's a bug or intended design: report as Low/Info, don't discard.
(Missed Mediums in StakeFlow and elsewhere by assuming "accepted risk.")

## Coverage discipline (the lesson that cost two Highs)

Day one: list EVERY file in scope and read each at least once BEFORE going deep on
any. Both Pump Science Highs and 3 of 4 WOOFi findings were in files never opened.
Coverage means the whole scope, not the whole main file.

## Calibration log (what I caught vs. missed, per contest)

Update after every shadow audit / contest calibration. This maps my blind spots.

| Contest | Caught | Missed | Lesson |
|---------|--------|--------|--------|
| Orderly | H-01 mint substitution (#37), H-02 receiver binding (#146) — both Sponsor Confirmed | — | Exact-vector framing validated (#146) where the approximate framing (#142) was disputed |
| Pump Science | M-01 last-buy fee mismatch | Both Highs (files never opened) | Coverage: read every file day one |
| WOOFi | 2 of 4 (bump-seed DoS, init front-running) | 2 Highs (scope not fully covered) | Same coverage lesson |
| StakeFlow | Two executable PoCs | Mediums assumed "accepted risk" | Report Low/Info when unsure, don't discard |
| MissionX | Role-separation bypass (High), dup-submitter griefing (Medium) | — | — |

## Account-model classes (from Ackee common-attack-vectors study)

**Duplicate mutable accounts.** An instruction takes 2+ mutable accounts of the SAME
type and the logic assumes they're distinct (transfers between them, updates both).
No constraint forces them to differ. Attacker passes the SAME account twice -> Anchor
deserializes into two in-memory structs pointing at one on-chain account; writes clash,
last-write-wins, breaking value conservation (e.g. mint funds from nothing in a trade).
Signal: two `Account<'info, T>` of same T, both mut, no `key() != key()` check.
Fix: `constraint = vault_a.key() != vault_b.key()`. (Each account passes its own checks
individually — the bug ONLY shows when they're the same, so it's easy to miss.)

**Type cosplay.** Account data is raw bytes; if two account types have the SAME byte
size and the code deserializes without a discriminator check, one type can masquerade
as another. Signal: manual deserialization (`try_from_slice`) on `AccountInfo` /
`UncheckedAccount` (/// CHECK) then read as a specific type; or native (non-Anchor)
programs. Attacker picks which struct the program thinks it's reading (e.g. controls a
field that lands on an `authority` position). Fix: use `Account<'info, T>` — Anchor's
8-byte discriminator makes mismatched types revert. Reflex: every AccountInfo/Unchecked
read as data -> "could another same-size account be substituted here?"

**Re-initialization (init_if_needed).** `init_if_needed` without guards lets an attacker
call the init instruction again to overwrite an existing account's data. Signal: any
`init_if_needed` — check whether a second call can reset critical state.

**Revival attack.** A "closed" account revived because the attacker refunds its rent
lamports in the SAME tx before garbage collection (GC runs only after tx completes).
Signal: manual account closing that only transfers lamports without zeroing data +
setting the closed discriminator. Connects to the Perceptron rent-not-reclaimed note.

## Defensa modelo: como se ve un sistema de rewards/emision bien construido

Referencia de "como deberia ser". Cuando audites un protocolo de rewards/minting y
FALTE alguna de estas defensas, ahi esta el finding.

- **Solvencia con doble guard.** No alcanza con un contador. Un sistema robusto verifica
  (a) la contabilidad: next_allocated <= pool y next_claimed <= pool, Y ADEMAS
  (b) el balance real del vault antes de transferir: vault.amount >= amount. El primero
  protege la logica; el segundo protege contra desincronizacion contador-vs-real.
  Senal de finding: si solo hay contador y no se chequea el balance real (o viceversa).

- **Espacio de cuentas con InitSpace + test.** Los structs usan #[derive(InitSpace)] y
  LEN = 8 + INIT_SPACE (nunca tamanos hardcodeados), con un test que serializa la cuenta
  con valores MAX y compara contra INIT_SPACE. Senal de finding: space = <numero
  hardcodeado> sin test -> puede estar mal calculado (over/under-allocation).

- **Pesos/porcentajes normalizados y acotados.** Cuando un input define proporciones,
  validar que cada uno este en rango Y que la suma sea exactamente la escala
  (total == SCALE). Senal: si los pesos no se validan a sumar la escala, el total puede
  inflarse y romper la proporcionalidad del reparto.

- **Leer-antes-de-CPI (evita account reloading bug).** Patron correcto: leer el balance/
  campo ANTES de la CPI que lo modifica, actuar con el valor local, y NO releer despues.
  Si un programa lee vault.amount DESPUES de un mint_to/transfer sin .reload(), usa datos
  viejos. Senal de finding: lectura de cuenta modificada post-CPI sin reload.

- **Programa objetivo de CPI fijado por tipo.** token_program: Program<'info, Token>
  (no AccountInfo) hace que Anchor valide el program ID. Senal de finding (arbitrary CPI):
  CPI cuyo programa objetivo viene de un AccountInfo/Unchecked sin address=.

- **Signer PDA via new_with_signer.** Una UncheckedAccount que es authority de una CPI NO
  es un agujero si firma como PDA con seeds fijas (new_with_signer). No se puede sustituir.
  Senal de finding: solo si esa authority se LEE como data o no esta atada a seeds/address.

## Signer authorization (clase madre de control de acceso)

Firmar != estar autorizado. `Signer` prueba IDENTIDAD (esta cuenta firmo), NO PERMISO
(esta cuenta puede hacer esta accion). El bug: una instruccion modifica/mueve algo,
tiene un Signer, pero no verifica que ese signer sea el authority/owner de la cuenta
afectada -> cualquiera que firme opera sobre datos/fondos de otro.

Senal: cuenta con campo `authority`/`owner` guardado + instruccion que la toca + NO hay
`has_one = authority` ni `require!(x.authority == signer.key())`. El signer suelto sin
binding al dueno es el olor.

Fix: `has_one = authority` en el struct, o comparacion explicita del signer contra el
campo owner de la cuenta.

Detectado intuitivamente en varios audits previos:
- Retiro cross-chain donde el caller no estaba atado al receiver del payload -> cualquiera
  cobraba el retiro de otro (High).
- Claim donde SI estaba el user == signer.key() -> defensa correcta de esta clase.
Reflejo permanente: cada Signer que actua sobre una cuenta con dueno -> "se verifica que
el signer ES el dueno?".

## Ownership check
Una cuenta (tipico: TokenAccount) usada sin verificar su owner ni su mint. Atacante
pasa un token account malicioso propio del mismo tipo -> pasa deserializacion, engana
la logica. Senal: TokenAccount/Account<T> sin constraints que lo aten a mint/authority
esperados. Fix: token::mint = mint, token::authority = owner. Reflejo: "este token
account es del mint y dueno que asumo, o me pueden pasar otro?".

## Account data matching
Instruccion que modifica/actua sobre una cuenta sin verificar que sea LA cuenta correcta
con los datos esperados. Primo de signer auth pero enfocado en QUE cuenta se toca (no
quien firma). Senal: cuenta modificada sin has_one/seeds/comparacion que la ate al
contexto. Reflejo: "es LA cuenta correcta, o cualquiera del tipo pasa?".
Nota: el mint substitution (deposito de mint no validado contra allowed_token.mint) es un
caso de esta clase — ya cazado en la practica (Orderly H-01).

## PDA privileges
Un PDA firma una accion privilegiada (transfer/mint/withdraw) pero no se verifica que el
CALLER tenga derecho a usar ESE PDA. Si las seeds del PDA no incluyen la identidad del
dueno, un atacante usa el PDA de otro para autorizar acciones sobre fondos ajenos. Senal:
PDA que firma via new_with_signer/invoke_signed donde las seeds NO incluyen la key del
usuario dueno, o no se valida al caller. Fix: incluir owner.key() en las seeds, o has_one.
Distincion fina con signer auth: signer auth = "el que firma es el dueno?"; pda privileges
= "el caller tiene derecho a usar este PDA que firma por el?".
Nota: un mint_authority PDA con seeds fijas de config (uno global, no por usuario) NO
sufre esto — es PDA de sistema. El bug aplica cuando el PDA deberia ser por-usuario.

---
## Cobertura Ackee: 11/11 clases estudiadas
duplicate-mutable, type-cosplay, re-initialization, revival, account-reloading,
arbitrary-cpi, signer-authorization, ownership-check, account-data-matching,
pda-privileges, initialization-frontrunning (esta ultima = el High de rebate_manager).
