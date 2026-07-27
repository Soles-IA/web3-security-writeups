use anchor_lang::prelude::*;
use anchor_lang::solana_program::program::invoke_signed;
use anchor_lang::solana_program::instruction::{Instruction, AccountMeta};

declare_id!("DjRJTM2gehb5dmJ1SQnPhFKbPcRqAZynoMtKJGBn5CR3");

#[program]
pub mod poc_cpi_test {
    use super::*;

    // Reproduce el patron de Pump Science intialize_meta:
    // el PDA (mint authority) firma un CPI a un programa ARBITRARIO.
    pub fn create_with_meta<'info>(
        ctx: Context<'_, '_, '_, 'info, CreateWithMeta<'info>>,
    ) -> Result<()> {
        let mint_key = ctx.accounts.mint.key();
        let bump = ctx.bumps.mint_authority;
        let seeds: &[&[u8]] = &[b"auth", mint_key.as_ref(), &[bump]];
        let signer: &[&[&[u8]]] = &[seeds];

        let mut metas = vec![
            AccountMeta::new(ctx.accounts.mint.key(), false),
            AccountMeta::new_readonly(ctx.accounts.mint_authority.key(), true),
        ];
        let mut infos = vec![
            ctx.accounts.mint.to_account_info(),
            ctx.accounts.mint_authority.to_account_info(),
        ];
        for acc in ctx.remaining_accounts.iter() {
            metas.push(AccountMeta {
                pubkey: acc.key(),
                is_signer: false,
                is_writable: acc.is_writable,
            });
            infos.push(acc.clone());
        }

        let ix = Instruction {
            program_id: ctx.accounts.metadata_program.key(),
            accounts: metas,
            data: vec![0x6e, 0x42, 0x7d, 0xb2, 0x5b, 0x59, 0x69, 0x5d],
        };

        invoke_signed(&ix, &infos, signer)?;
        msg!("victim: CPI firmado enviado al metadata_program arbitrario");
        Ok(())
    }
}

#[derive(Accounts)]
pub struct CreateWithMeta<'info> {
    #[account(mut)]
    pub mint: Signer<'info>,
    #[account(seeds = [b"auth", mint.key().as_ref()], bump)]
    /// CHECK: PDA mint authority
    pub mint_authority: UncheckedAccount<'info>,
    /// CHECK: el programa metadata — atacante lo controla
    pub metadata_program: UncheckedAccount<'info>,
}
