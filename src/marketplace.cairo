#[starknet::contract]
mod FreelanceMarketplace {
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use array::ArrayTrait;
    use traits::Into;
    use traits::TryInto;
    use option::OptionTrait;
    use box::BoxTrait;
    use integer::u256_from_felt252;
    use starknet::get_block_timestamp;
    use zeroable::Zeroable;

    // Job status enum
    #[derive(Drop, Copy, Serde, starknet::Store)]
    enum JobStatus {
        Open,
        Assigned,
        Submitted,
        Disputed,
        Completed,
        Cancelled
    }

    // Job struct
    #[derive(Drop, Copy, Serde, starknet::Store)]
    struct Job {
        id: u256,
        client: ContractAddress,
        freelancer: ContractAddress,
        payment_amount: u256,
        deadline: u64,
        status: JobStatus,
        description: felt252,
        created_at: u64
    }

    // Storage
    #[storage]
    struct Storage {
        // Job-related storage
        next_job_id: u256,
        jobs: LegacyMap<u256, Job>,
        client_jobs: LegacyMap<(ContractAddress, u256), bool>,
        freelancer_jobs: LegacyMap<(ContractAddress, u256), bool>,
        
        // Platform fee percentage (in basis points, e.g. 250 = 2.5%)
        platform_fee_bps: u16,
        platform_wallet: ContractAddress,
        
        // Token contract for payments (assuming using an ERC20 token)
        payment_token: ContractAddress,
        
        // Owner
        owner: ContractAddress
    }

    // Events
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        JobCreated: JobCreated,
        JobAssigned: JobAssigned,
        WorkSubmitted: WorkSubmitted,
        JobCompleted: JobCompleted,
        JobCancelled: JobCancelled,
        JobDisputed: JobDisputed,
        OwnershipTransferred: OwnershipTransferred
    }

    #[derive(Drop, starknet::Event)]
    struct JobCreated {
        #[key]
        job_id: u256,
        #[key]
        client: ContractAddress,
        payment_amount: u256,
        deadline: u64,
        description: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct JobAssigned {
        #[key]
        job_id: u256,
        #[key]
        freelancer: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct WorkSubmitted {
        #[key]
        job_id: u256,
        #[key]
        freelancer: ContractAddress
    }

    #[derive(Drop, starknet::Event)]
    struct JobCompleted {
        #[key]
        job_id: u256,
        #[key]
        client: ContractAddress,
        #[key]
        freelancer: ContractAddress,
        payment_amount: u256
    }

    #[derive(Drop, starknet::Event)]
    struct JobCancelled {
        #[key]
        job_id: u256,
        reason: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct JobDisputed {
        #[key]
        job_id: u256,
        #[key]
        disputer: ContractAddress,
        reason: felt252
    }

    #[derive(Drop, starknet::Event)]
    struct OwnershipTransferred {
        #[key]
        previous_owner: ContractAddress,
        #[key]
        new_owner: ContractAddress
    }

    // Error codes
    mod Errors {
        const INVALID_JOB_ID: felt252 = 'Invalid job ID';
        const INVALID_STATUS: felt252 = 'Invalid job status';
        const UNAUTHORIZED: felt252 = 'Unauthorized caller';
        const DEADLINE_PASSED: felt252 = 'Deadline has passed';
        const ONLY_OWNER: felt252 = 'Only owner can call';
        const INVALID_AMOUNT: felt252 = 'Invalid payment amount';
        const ALREADY_ASSIGNED: felt252 = 'Job already assigned';
        const SAME_ADDRESS: felt252 = 'Same address for client/worker';
        const PAYMENT_FAILED: felt252 = 'Payment transfer failed';
    }

    // Constructor
    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        payment_token: ContractAddress,
        platform_fee_bps: u16,
        platform_wallet: ContractAddress
    ) {
        self.next_job_id.write(1);
        self.owner.write(owner);
        self.payment_token.write(payment_token);
        self.platform_fee_bps.write(platform_fee_bps);
        self.platform_wallet.write(platform_wallet);
    }

    // External functions
    #[external(v0)]
    impl FreelanceMarketplaceImpl of super::IFreelanceMarketplace<ContractState> {
        // Create a new job
        fn create_job(
            ref self: ContractState,
            payment_amount: u256,
            deadline: u64,
            description: felt252
        ) -> u256 {
            // Check valid parameters
            assert(payment_amount > 0, Errors::INVALID_AMOUNT);
            let current_time = get_block_timestamp();
            assert(deadline > current_time, Errors::DEADLINE_PASSED);
            
            let client = get_caller_address();
            let job_id = self.next_job_id.read();
            
            // Create job record
            let job = Job {
                id: job_id,
                client: client,
                freelancer: contract_address_const::<0>(),
                payment_amount: payment_amount,
                deadline: deadline,
                status: JobStatus::Open,
                description: description,
                created_at: current_time
            };
            
            // Store job data
            self.jobs.write(job_id, job);
            self.client_jobs.write((client, job_id), true);
            
            // Update job counter
            self.next_job_id.write(job_id + 1);
            
            // Transfer payment from client to contract (escrow)
            // This requires approval from the client to the contract
            let payment_token = self.payment_token.read();
            let transfer_success = IERC20Dispatcher { contract_address: payment_token }
                .transferFrom(client, starknet::get_contract_address(), payment_amount);
            assert(transfer_success, Errors::PAYMENT_FAILED);
            
            // Emit event
            self.emit(JobCreated {
                job_id: job_id,
                client: client,
                payment_amount: payment_amount,
                deadline: deadline,
                description: description
            });
            
            job_id
        }
        
        // Freelancer applies for a job
        fn apply_for_job(ref self: ContractState, job_id: u256) {
            let freelancer = get_caller_address();
            let mut job = self.jobs.read(job_id);
            
            // Validate job
            assert(job.id == job_id, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Open, Errors::INVALID_STATUS);
            assert(freelancer != job.client, Errors::SAME_ADDRESS);
            
            // Update job state
            job.freelancer = freelancer;
            job.status = JobStatus::Assigned;
            self.jobs.write(job_id, job);
            self.freelancer_jobs.write((freelancer, job_id), true);
            
            // Emit event
            self.emit(JobAssigned { job_id: job_id, freelancer: freelancer });
        }
        
        // Freelancer submits work
        fn submit_work(ref self: ContractState, job_id: u256) {
            let freelancer = get_caller_address();
            let mut job = self.jobs.read(job_id);
            
            // Validate job
            assert(job.id == job_id, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Assigned, Errors::INVALID_STATUS);
            assert(job.freelancer == freelancer, Errors::UNAUTHORIZED);
            
            // Update job state
            job.status = JobStatus::Submitted;
            self.jobs.write(job_id, job);
            
            // Emit event
            self.emit(WorkSubmitted { job_id: job_id, freelancer: freelancer });
        }
        
        // Client approves work and releases payment
        fn approve_work(ref self: ContractState, job_id: u256) {
            let client = get_caller_address();
            let mut job = self.jobs.read(job_id);
            
            // Validate job
            assert(job.id == job_id, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Submitted, Errors::INVALID_STATUS);
            assert(job.client == client, Errors::UNAUTHORIZED);
            
            // Calculate platform fee
            let platform_fee = (job.payment_amount * self.platform_fee_bps.into()) / 10000;
            let freelancer_payment = job.payment_amount - platform_fee;
            
            // Transfer payments
            let payment_token = self.payment_token.read();
            let platform_wallet = self.platform_wallet.read();
            
            // Transfer platform fee if applicable
            if platform_fee > 0 {
                let fee_transfer = IERC20Dispatcher { contract_address: payment_token }
                    .transfer(platform_wallet, platform_fee);
                assert(fee_transfer, Errors::PAYMENT_FAILED);
            }
            
            // Transfer payment to freelancer
            let freelancer_transfer = IERC20Dispatcher { contract_address: payment_token }
                .transfer(job.freelancer, freelancer_payment);
            assert(freelancer_transfer, Errors::PAYMENT_FAILED);
            
            // Update job state
            job.status = JobStatus::Completed;
            self.jobs.write(job_id, job);
            
            // Emit event
            self.emit(JobCompleted {
                job_id: job_id,
                client: client,
                freelancer: job.freelancer,
                payment_amount: job.payment_amount
            });
        }
        
        // Either party can dispute the job
        fn dispute_job(ref self: ContractState, job_id: u256, reason: felt252) {
            let caller = get_caller_address();
            let mut job = self.jobs.read(job_id);
            
            // Validate job
            assert(job.id == job_id, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Assigned || job.status == JobStatus::Submitted, Errors::INVALID_STATUS);
            assert(caller == job.client || caller == job.freelancer, Errors::UNAUTHORIZED);
            
            // Update job state
            job.status = JobStatus::Disputed;
            self.jobs.write(job_id, job);
            
            // Emit event
            self.emit(JobDisputed { job_id: job_id, disputer: caller, reason: reason });
        }
        
        // Owner can resolve disputes
        fn resolve_dispute(
            ref self: ContractState,
            job_id: u256,
            client_percent: u16,
            freelancer_percent: u16
        ) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), Errors::ONLY_OWNER);
            
            let mut job = self.jobs.read(job_id);
            
            // Validate job
            assert(job.id == job_id, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Disputed, Errors::INVALID_STATUS);
            assert(client_percent + freelancer_percent <= 100 * 100, 'Invalid percentages'); // Check total <= 100%
            
            let payment_token = self.payment_token.read();
            let platform_wallet = self.platform_wallet.read();
            
            // Calculate payments
            let platform_fee = (job.payment_amount * self.platform_fee_bps.into()) / 10000;
            let distributable_amount = job.payment_amount - platform_fee;
            
            let client_refund = (distributable_amount * client_percent.into()) / 10000;
            let freelancer_payment = (distributable_amount * freelancer_percent.into()) / 10000;
            let remaining = distributable_amount - client_refund - freelancer_payment;
            
            // Transfer platform fee
            if platform_fee > 0 {
                let fee_transfer = IERC20Dispatcher { contract_address: payment_token }
                    .transfer(platform_wallet, platform_fee);
                assert(fee_transfer, Errors::PAYMENT_FAILED);
            }
            
            // Transfer client refund if applicable
            if client_refund > 0 {
                let client_transfer = IERC20Dispatcher { contract_address: payment_token }
                    .transfer(job.client, client_refund);
                assert(client_transfer, Errors::PAYMENT_FAILED);
            }
            
            // Transfer freelancer payment if applicable
            if freelancer_payment > 0 {
                let freelancer_transfer = IERC20Dispatcher { contract_address: payment_token }
                    .transfer(job.freelancer, freelancer_payment);
                assert(freelancer_transfer, Errors::PAYMENT_FAILED);
            }
            
            // Transfer any remaining amount to platform
            if remaining > 0 {
                let remaining_transfer = IERC20Dispatcher { contract_address: payment_token }
                    .transfer(platform_wallet, remaining);
                assert(remaining_transfer, Errors::PAYMENT_FAILED);
            }
            
            // Update job state
            job.status = JobStatus::Completed;
            self.jobs.write(job_id, job);
            
            // Emit event
            self.emit(JobCompleted {
                job_id: job_id,
                client: job.client,
                freelancer: job.freelancer,
                payment_amount: job.payment_amount
            });
        }
        
        // Client can cancel job if not yet assigned
        fn cancel_job(ref self: ContractState, job_id: u256) {
            let client = get_caller_address();
            let mut job = self.jobs.read(job_id);
            
            // Validate job
            assert(job.id == job_id, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Open, Errors::INVALID_STATUS);
            assert(job.client == client, Errors::UNAUTHORIZED);
            
            // Return payment to client
            let payment_token = self.payment_token.read();
            let transfer_success = IERC20Dispatcher { contract_address: payment_token }
                .transfer(client, job.payment_amount);
            assert(transfer_success, Errors::PAYMENT_FAILED);
            
            // Update job state
            job.status = JobStatus::Cancelled;
            self.jobs.write(job_id, job);
            
            // Emit event
            self.emit(JobCancelled { job_id: job_id, reason: 'Cancelled by client' });
        }
        
        // Admin functions
        fn update_platform_fee(ref self: ContractState, new_fee_bps: u16) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), Errors::ONLY_OWNER);
            assert(new_fee_bps <= 3000, 'Fee too high'); // Max 30%
            
            self.platform_fee_bps.write(new_fee_bps);
        }
        
        fn update_platform_wallet(ref self: ContractState, new_wallet: ContractAddress) {
            let caller = get_caller_address();
            assert(caller == self.owner.read(), Errors::ONLY_OWNER);
            assert(!new_wallet.is_zero(), 'Zero address not allowed');
            
            self.platform_wallet.write(new_wallet);
        }
        
        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let caller = get_caller_address();
            let current_owner = self.owner.read();
            assert(caller == current_owner, Errors::ONLY_OWNER);
            assert(!new_owner.is_zero(), 'Zero address not allowed');
            
            self.owner.write(new_owner);
            
            self.emit(OwnershipTransferred {
                previous_owner: current_owner,
                new_owner: new_owner
            });
        }
        
        // View functions
        fn get_job(self: @ContractState, job_id: u256) -> Job {
            self.jobs.read(job_id)
        }
        
        fn get_platform_fee(self: @ContractState) -> u16 {
            self.platform_fee_bps.read()
        }
        
        fn get_owner(self: @ContractState) -> ContractAddress {
            self.owner.read()
        }
    }
}

// Interface definition
#[starknet::interface]
trait IFreelanceMarketplace<TContractState> {
    fn create_job(ref self: TContractState, payment_amount: u256, deadline: u64, description: felt252) -> u256;
    fn apply_for_job(ref self: TContractState, job_id: u256);
    fn submit_work(ref self: TContractState, job_id: u256);
    fn approve_work(ref self: TContractState, job_id: u256);
    fn dispute_job(ref self: TContractState, job_id: u256, reason: felt252);
    fn resolve_dispute(ref self: TContractState, job_id: u256, client_percent: u16, freelancer_percent: u16);
    fn cancel_job(ref self: TContractState, job_id: u256);
    fn update_platform_fee(ref self: TContractState, new_fee_bps: u16);
    fn update_platform_wallet(ref self: TContractState, new_wallet: ContractAddress);
    fn transfer_ownership(ref self: TContractState, new_owner: ContractAddress);
    fn get_job(self: @TContractState, job_id: u256) -> Job;
    fn get_platform_fee(self: @TContractState) -> u16;
    fn get_owner(self: @TContractState) -> ContractAddress;
}

// ERC20 interface for payment token
#[starknet::interface]
trait IERC20<TContractState> {
    fn balanceOf(self: @TContractState, account: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, recipient: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn transferFrom(ref self: TContractState, sender: ContractAddress, recipient: ContractAddress, amount: u256) -> bool;
}