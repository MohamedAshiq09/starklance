#[starknet::contract]
mod FreelanceMarketplace {
    use starknet::{ContractAddress, get_caller_address, get_block_timestamp, get_contract_address};
    use starknet::class_hash::ClassHash;
    use starknet::storage_access::StorageBaseAddress;
    use starknet::SyscallResultTrait;
    use core::num::traits::Zero;
    use core::traits::{Into, TryInto};
    use core::option::OptionTrait;
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait
    };
    use project::interfaces::IFreelanceMarketplace;
    use project::models::{Job, JobStatus};

    #[storage]
    struct Storage {
        next_job_id: u256,
        jobs: Map<u256, Job>,
        client_jobs: Map<(ContractAddress, u256), bool>,
        freelancer_jobs: Map<(ContractAddress, u256), bool>,
        platform_fee_bps: u16,
        platform_wallet: ContractAddress,
        payment_token: ContractAddress,
        owner: ContractAddress
    }

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

    #[constructor]
    fn constructor(
        ref self: ContractState,
        owner: ContractAddress,
        payment_token: ContractAddress,
        platform_fee_bps: u16,
        platform_wallet: ContractAddress
    ) {
        self.next_job_id.write(1_u256);
        self.owner.write(owner);
        self.payment_token.write(payment_token);
        self.platform_fee_bps.write(platform_fee_bps);
        self.platform_wallet.write(platform_wallet);
    }

    #[external(v0)]
    impl FreelanceMarketplaceImpl of IFreelanceMarketplace<ContractState> {
        fn create_job(
            ref self: ContractState,
            payment_amount: u256,
            deadline: u64,
            description: felt252
        ) -> u256 {
            assert(payment_amount > 0, Errors::INVALID_AMOUNT);
            let current_time = get_block_timestamp();
            assert(deadline > current_time, Errors::DEADLINE_PASSED);

            let client = get_caller_address();
            let job_id = self.next_job_id.read();

            let job = Job {
                id: job_id,
                client,
                freelancer: ContractAddress::zero(),
                payment_amount,
                deadline,
                status: JobStatus::Open,
                description,
                created_at: current_time
            };

            self.jobs.write(job_id, job);
            self.client_jobs.write((client, job_id), true);
            self.next_job_id.write(job_id + 1);

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            let success = payment_token.transfer_from(
                client,
                get_contract_address(),
                payment_amount
            );
            assert(success, Errors::PAYMENT_FAILED);

            self.emit(JobCreated { job_id, client, payment_amount, deadline, description });
            job_id
        }

        fn apply_for_job(ref self: ContractState, job_id: u256) {
            let freelancer = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id != 0, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Open, Errors::INVALID_STATUS);
            assert(freelancer != job.client, Errors::SAME_ADDRESS);

            job.freelancer = freelancer;
            job.status = JobStatus::Assigned;
            self.jobs.write(job_id, job);
            self.freelancer_jobs.write((freelancer, job_id), true);

            self.emit(JobAssigned { job_id, freelancer });
        }

        fn submit_work(ref self: ContractState, job_id: u256) {
            let freelancer = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id != 0, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Assigned, Errors::INVALID_STATUS);
            assert(job.freelancer == freelancer, Errors::UNAUTHORIZED);

            job.status = JobStatus::Submitted;
            self.jobs.write(job_id, job);

            self.emit(WorkSubmitted { job_id, freelancer });
        }

        fn approve_work(ref self: ContractState, job_id: u256) {
            let client = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id != 0, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Submitted, Errors::INVALID_STATUS);
            assert(job.client == client, Errors::UNAUTHORIZED);

            let platform_fee = (job.payment_amount * self.platform_fee_bps.read().into()) / 10000;
            let freelancer_payment = job.payment_amount - platform_fee;

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            
            if platform_fee > 0 {
                let platform_success = payment_token.transfer(self.platform_wallet.read(), platform_fee);
                assert(platform_success, Errors::PAYMENT_FAILED);
            }
            
            let freelancer_success = payment_token.transfer(job.freelancer, freelancer_payment);
            assert(freelancer_success, Errors::PAYMENT_FAILED);

            job.status = JobStatus::Completed;
            self.jobs.write(job_id, job);

            self.emit(JobCompleted { job_id, client, freelancer: job.freelancer, payment_amount: job.payment_amount });
        }

        fn dispute_job(ref self: ContractState, job_id: u256, reason: felt252) {
            let caller = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id != 0, Errors::INVALID_JOB_ID);
            assert(
                job.status == JobStatus::Assigned || job.status == JobStatus::Submitted,
                Errors::INVALID_STATUS
            );
            assert(caller == job.client || caller == job.freelancer, Errors::UNAUTHORIZED);

            job.status = JobStatus::Disputed;
            self.jobs.write(job_id, job);

            self.emit(JobDisputed { job_id, disputer: caller, reason });
        }

        fn resolve_dispute(
            ref self: ContractState,
            job_id: u256,
            client_percent: u16,
            freelancer_percent: u16
        ) {
            assert(get_caller_address() == self.owner.read(), Errors::ONLY_OWNER);
            let mut job = self.jobs.read(job_id);

            assert(job.id != 0, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Disputed, Errors::INVALID_STATUS);
            assert(client_percent + freelancer_percent <= 10000, 'Invalid percentages');

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            let platform_fee = (job.payment_amount * self.platform_fee_bps.read().into()) / 10000;
            let distributable = job.payment_amount - platform_fee;

            let client_refund = (distributable * client_percent.into()) / 10000;
            let freelancer_payment = (distributable * freelancer_percent.into()) / 10000;
            let remaining = distributable - client_refund - freelancer_payment;

            if platform_fee > 0 {
                let platform_success = payment_token.transfer(self.platform_wallet.read(), platform_fee);
                assert(platform_success, Errors::PAYMENT_FAILED);
            }
            
            if client_refund > 0 {
                let client_success = payment_token.transfer(job.client, client_refund);
                assert(client_success, Errors::PAYMENT_FAILED);
            }
            
            if freelancer_payment > 0 {
                let freelancer_success = payment_token.transfer(job.freelancer, freelancer_payment);
                assert(freelancer_success, Errors::PAYMENT_FAILED);
            }
            
            if remaining > 0 {
                let remaining_success = payment_token.transfer(self.platform_wallet.read(), remaining);
                assert(remaining_success, Errors::PAYMENT_FAILED);
            }

            job.status = JobStatus::Completed;
            self.jobs.write(job_id, job);

            self.emit(JobCompleted {
                job_id,
                client: job.client,
                freelancer: job.freelancer,
                payment_amount: job.payment_amount
            });
        }

        fn cancel_job(ref self: ContractState, job_id: u256) {
            let client = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id != 0, Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Open, Errors::INVALID_STATUS);
            assert(job.client == client, Errors::UNAUTHORIZED);

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            let success = payment_token.transfer(client, job.payment_amount);
            assert(success, Errors::PAYMENT_FAILED);

            job.status = JobStatus::Cancelled;
            self.jobs.write(job_id, job);

            self.emit(JobCancelled { job_id, reason: 'Cancelled by client' });
        }

        fn update_platform_fee(ref self: ContractState, new_fee_bps: u16) {
            assert(get_caller_address() == self.owner.read(), Errors::ONLY_OWNER);
            assert(new_fee_bps <= 3000, 'Fee too high');
            self.platform_fee_bps.write(new_fee_bps);
        }

        fn update_platform_wallet(ref self: ContractState, new_wallet: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), Errors::ONLY_OWNER);
            assert(!new_wallet.is_zero(), 'Zero address not allowed');
            self.platform_wallet.write(new_wallet);
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let caller = get_caller_address();
            let current_owner = self.owner.read();
            assert(caller == current_owner, Errors::ONLY_OWNER);
            assert(!new_owner.is_zero(), 'Zero address not allowed');
            
            self.owner.write(new_owner);
            self.emit(OwnershipTransferred { previous_owner: current_owner, new_owner });
        }

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