use anchor_lang::prelude::*;

declare_id!("7gRt6w2Q7BKMZ7FgyC8dvJwm6BBdVYWWZsiSMW2wEndT");

#[program]
pub mod anchor_poc_031 {
    use super::*;

    pub fn initialize(ctx: Context<Initialize>) -> Result<()> {
        msg!("Greetings from: {:?}", ctx.program_id);
        Ok(())
    }
}

#[derive(Accounts)]
pub struct Initialize {}
