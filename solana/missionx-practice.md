# MissionX (Solana Audit Arena, Week 2) — practice audit

Anchor + Token-2022 bounty marketplace, ~2400 LoC, two parallel state machines.
Self-directed practice audit (contest window closed; not a submission).

[H-XX] Mission creator can self-accept and self-adjudicate, capturing the player token allocation

Severity: High — access control bypass (role separation)

Description

MissionX assumes a separation between the party that performs a mission (player) and the party that adjudicates it (moderator, or the creator via the documented creator path). Two independently reasonable design choices combine to break that assumption:

accept_missionx never validates that the accepting player is not the mission creator. The instruction checks mission status, expiry and nothing about the signer's identity relative to missionx_state.creator:

rust
missionx_state.submitters[0] = Some(ctx.accounts.player.key());
// no `require!(player.key() != missionx_state.creator, ...)`

complete_missionx skips the moderator check entirely when the signer is the creator (documented behaviour):

rust
if ctx.accounts.moderator.key() != ctx.accounts.missionx_creator.key() {
    let config = ctx.accounts.moderator_config.as_ref().unwrap();
    ensure_moderator_enabled(config.deref())?;
}

Individually each is defensible. Together they let one address occupy the creator, player and adjudicator roles simultaneously, with no third party involved at any point.

Attack chain

Attacker calls create_missionx, depositing payout_amount SOL and paying creation_fee.
Buyers trade the mission's bonding-curve token until migration_threshold is reached in buy, setting trade_status = MigrationRequired. (Precondition — token payouts in do_token_payout are gated on missionx_reached_migration.)
Attacker calls accept_missionx with their own key, becoming submitters[0].
Attacker calls complete_missionx(is_successful = true) signing as the creator, bypassing ensure_moderator_enabled.
do_token_payout transfers token_player_payout to the attacker's ATA and token_creator_payout to the same attacker's ATA, and payout_amount lamports are returned to the attacker as the player.

Impact

The role separation the protocol depends on is not enforced. Concretely, comparing the resulting state against an honest completion: token_player_payout — the allocation reserved to compensate a third party for performing the mission — is transferred to the creator instead, and the creator recovers payout_amount in full. Net cost of the entire cycle is creation_fee.

No mission work is ever performed, and no independent party ever reviews the outcome. The attacker is an ordinary user, not a privileged role, so this is not covered by moderator or owner trust assumptions.

Note on scope of impact: bonding-curve buyers are not directly drained by this specific flow — the same token_player_payout leaves the vault whether the completion is honest or not. The loss is the misdirection of that reserved allocation and the removal of adjudication independence, which allows sham missions to be run at near-zero cost.

Recommended fix

Enforce role separation at acceptance:

rust
require!(
    ctx.accounts.player.key() != ctx.accounts.missionx_state.creator,
    MissionxErrors::CreatorCannotBePlayer
);

Apply the same check in accept_missionx_multi. If the creator path in complete_missionx is retained, additionally reject the case where the adjudicating creator is also a listed submitter.

