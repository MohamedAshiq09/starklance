use starknet::ContractAddress;
use super::models::{Job, JobStatus};

#[starknet::interface]
pub trait IFreelanceMarketplace<TContractState> {
    fn create_job(
        ref self: TContractState, 
        payment_amount: u256,
        deadline: u64,
        description: felt252
    ) -> u256;

    fn apply_for_job(ref self: TContractState, job_id: u256);
    
    fn submit_work(ref self: TContractState, job_id: u256);
    
    fn approve_work(ref self: TContractState, job_id: u256);
    
    fn dispute_job(ref self: TContractState, job_id: u256, reason: felt252);
    
    fn resolve_dispute(
        ref self: TContractState,
        job_id: u256,
        client_percent: u16,
        freelancer_percent: u16
    );
    
    fn cancel_job(ref self: TContractState, job_id: u256);
    
    fn update_platform_fee(ref self: TContractState, new_fee_bps: u16);
    
    fn update_platform_wallet(ref self: TContractState, new_wallet: ContractAddress);
    
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    
    fn get_job(self: @TContractState, job_id: u256) -> Job;
    
    fn get_platform_fee(self: @TContractState) -> u16;
    
    fn get_owner(self: @TContractState) -> ContractAddress;
}