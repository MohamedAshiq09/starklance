#[derive(Copy, Drop, Serde, starknet::Store)]
enum JobStatus {
    Open,
    Assigned,
    Submitted,
    Disputed,
    Completed,
    Cancelled
}

#[derive(Copy, Drop, Serde, starknet::Store)]
struct Job {
    id: u256,
    client: starknet::ContractAddress,
    freelancer: starknet::ContractAddress,
    payment_amount: u256,
    deadline: u64,
    status: JobStatus,
    description: felt252,
    created_at: u64
}