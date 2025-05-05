#[derive(Copy, Drop, Serde, starknet::Store)]
pub enum JobStatus {
    Open,
    Assigned,
    Submitted,
    Completed,
    Disputed,
    Cancelled
}

#[derive(Copy, Drop, Serde, starknet::Store)]
pub struct Job {
    pub id: u256,
    pub client: starknet::ContractAddress,
    pub freelancer: starknet::ContractAddress,
    pub payment_amount: u256,
    pub deadline: u64,
    pub status: JobStatus,
    pub description: felt252,
    pub created_at: u64
}