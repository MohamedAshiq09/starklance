#[starknet::contract]
mod FreelanceMarketplace {
    use starknet::get_caller_address;
    use starknet::ContractAddress;
    use starknet::contract_address_const;
    use starknet::get_block_timestamp;
    use starknet::class_hash::ClassHash;
    use starknet::contract_address::ContractAddressZeroable;
    use zeroable::Zeroable;
    use traits::Into;
    use traits::TryInto;
    use option::OptionTrait;
    use array::ArrayTrait;
    use box::BoxTrait;
    use integer::u256_from_felt252;
    use starknet::{Store, SyscallResultTrait};

    // Required for IERC20 interactions
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait
    };

    // Job status enum
    #[derive(Copy, Drop, Serde, starknet::Store)]
    enum JobStatus {
        Open: (),
        Assigned: (),
        Submitted: (),
        Disputed: (),
        Completed: (),
        Cancelled: ()
    }

    // Job struct
    #[derive(Copy, Drop, Serde, starknet::Store)]
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
        next_job_id: u256,
        jobs: LegacyMap::<u256, Job>,
        client_jobs: LegacyMap::<(ContractAddress, u256), bool>,
        freelancer_jobs: LegacyMap::<(ContractAddress, u256), bool>,
        platform_fee_bps: u16,
        platform_wallet: ContractAddress,
        payment_token: ContractAddress,
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
    impl FreelanceMarketplaceImpl of super::IFreelanceMarketplace<ContractState> {
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
                client: client,
                freelancer: ContractAddressZeroable::zero(),
                payment_amount: payment_amount,
                deadline: deadline,
                status: JobStatus::Open(()),
                description: description,
                created_at: current_time
            };

            self.jobs.write(job_id, job);
            self.client_jobs.write((client, job_id), true);
            self.next_job_id.write(job_id + 1);

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            let success = payment_token.transfer_from(
                client,
                starknet::get_contract_address(),
                payment_amount
            );
            assert(success, Errors::PAYMENT_FAILED);

            self.emit(JobCreated {
                job_id: job_id,
                client: client,
                payment_amount: payment_amount,
                deadline: deadline,
                description: description
            });

            job_id
        }

        fn apply_for_job(ref self: ContractState, job_id: u256) {
            let freelancer = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id.is_non_zero(), Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Open(()), Errors::INVALID_STATUS);
            assert(freelancer != job.client, Errors::SAME_ADDRESS);

            job.freelancer = freelancer;
            job.status = JobStatus::Assigned(());
            self.jobs.write(job_id, job);
            self.freelancer_jobs.write((freelancer, job_id), true);

            self.emit(JobAssigned { job_id: job_id, freelancer: freelancer });
        }

        fn submit_work(ref self: ContractState, job_id: u256) {
            let freelancer = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id.is_non_zero(), Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Assigned(()), Errors::INVALID_STATUS);
            assert(job.freelancer == freelancer, Errors::UNAUTHORIZED);

            job.status = JobStatus::Submitted(());
            self.jobs.write(job_id, job);

            self.emit(WorkSubmitted { job_id: job_id, freelancer: freelancer });
        }

        fn approve_work(ref self: ContractState, job_id: u256) {
            let client = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id.is_non_zero(), Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Submitted(()), Errors::INVALID_STATUS);
            assert(job.client == client, Errors::UNAUTHORIZED);

            let platform_fee = (job.payment_amount * self.platform_fee_bps.read().into()) / 10000;
            let freelancer_payment = job.payment_amount - platform_fee;

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            
            if platform_fee > 0 {
                assert(payment_token.transfer(self.platform_wallet.read(), platform_fee), Errors::PAYMENT_FAILED);
            }
            assert(payment_token.transfer(job.freelancer, freelancer_payment), Errors::PAYMENT_FAILED);

            job.status = JobStatus::Completed(());
            self.jobs.write(job_id, job);

            self.emit(JobCompleted {
                job_id: job_id,
                client: client,
                freelancer: job.freelancer,
                payment_amount: job.payment_amount
            });
        }

        fn dispute_job(ref self: ContractState, job_id: u256, reason: felt252) {
            let caller = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id.is_non_zero(), Errors::INVALID_JOB_ID);
            let is_valid_status = match job.status {
                JobStatus::Assigned(_) => true,
                JobStatus::Submitted(_) => true,
                _ => false
            };
            assert(is_valid_status, Errors::INVALID_STATUS);
            assert(caller == job.client || caller == job.freelancer, Errors::UNAUTHORIZED);

            job.status = JobStatus::Disputed(());
            self.jobs.write(job_id, job);

            self.emit(JobDisputed { job_id: job_id, disputer: caller, reason: reason });
        }

        fn resolve_dispute(
            ref self: ContractState,
            job_id: u256,
            client_percent: u16,
            freelancer_percent: u16
        ) {
            assert(get_caller_address() == self.owner.read(), Errors::ONLY_OWNER);
            let mut job = self.jobs.read(job_id);

            assert(job.id.is_non_zero(), Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Disputed(()), Errors::INVALID_STATUS);
            assert(client_percent + freelancer_percent <= 10000, 'Invalid percentages');

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            let platform_fee = (job.payment_amount * self.platform_fee_bps.read().into()) / 10000;
            let distributable = job.payment_amount - platform_fee;

            let client_refund = (distributable * client_percent.into()) / 10000;
            let freelancer_payment = (distributable * freelancer_percent.into()) / 10000;
            let remaining = distributable - client_refund - freelancer_payment;

            if platform_fee > 0 {
                assert(payment_token.transfer(self.platform_wallet.read(), platform_fee), Errors::PAYMENT_FAILED);
            }
            if client_refund > 0 {
                assert(payment_token.transfer(job.client, client_refund), Errors::PAYMENT_FAILED);
            }
            if freelancer_payment > 0 {
                assert(payment_token.transfer(job.freelancer, freelancer_payment), Errors::PAYMENT_FAILED);
            }
            if remaining > 0 {
                assert(payment_token.transfer(self.platform_wallet.read(), remaining), Errors::PAYMENT_FAILED);
            }

            job.status = JobStatus::Completed(());
            self.jobs.write(job_id, job);

            self.emit(JobCompleted {
                job_id: job_id,
                client: job.client,
                freelancer: job.freelancer,
                payment_amount: job.payment_amount
            });
        }

        fn cancel_job(ref self: ContractState, job_id: u256) {
            let client = get_caller_address();
            let mut job = self.jobs.read(job_id);

            assert(job.id.is_non_zero(), Errors::INVALID_JOB_ID);
            assert(job.status == JobStatus::Open(()), Errors::INVALID_STATUS);
            assert(job.client == client, Errors::UNAUTHORIZED);

            let payment_token = IERC20Dispatcher { contract_address: self.payment_token.read() };
            assert(payment_token.transfer(client, job.payment_amount), Errors::PAYMENT_FAILED);

            job.status = JobStatus::Cancelled(());
            self.jobs.write(job_id, job);

            self.emit(JobCancelled { job_id: job_id, reason: 'Cancelled by client' });
        }

        fn update_platform_fee(ref self: ContractState, new_fee_bps: u16) {
            assert(get_caller_address() == self.owner.read(), Errors::ONLY_OWNER);
            assert(new_fee_bps <= 3000, 'Fee too high');
            self.platform_fee_bps.write(new_fee_bps);
        }

        fn update_platform_wallet(ref self: ContractState, new_wallet: ContractAddress) {
            assert(get_caller_address() == self.owner.read(), Errors::ONLY_OWNER);
            assert(new_wallet.is_non_zero(), 'Zero address not allowed');
            self.platform_wallet.write(new_wallet);
        }

        fn transfer_ownership(ref self: ContractState, new_owner: ContractAddress) {
            let caller = get_caller_address();
            let current_owner = self.owner.read();
            assert(caller == current_owner, Errors::ONLY_OWNER);
            assert(new_owner.is_non_zero(), 'Zero address not allowed');
            
            self.owner.write(new_owner);
            self.emit(OwnershipTransferred {
                previous_owner: current_owner,
                new_owner: new_owner
            });
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