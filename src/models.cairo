use starknet::ContractAddress;

#[derive(drop , copy , serde , starknet::store)]
enum JobStatus {
    open,
    assigned,
    submitted,
    disputed,
    completed, 
    cancelled
}

#[derive(drop , copy , serde , starknet::store)]
struct Job{
    id: u256,
    client: ContractAddress,
    freelancer: ContractAddress,
    payment_amount: u256,
    deadline: u64,
    status: JobStatus,
    description: felt252,
    created_at: u64
} 

