use starknet::{ContractAddress, get_caller_address};
use starknet::contract_address_const;
use array::ArrayTrait;
use zeroable::Zeroable;
use freelance_marketplace::interfaces::IERC20;

#[starknet::contract]
mod MockERC20 {
    use starknet::{ContractAddress, get_caller_address};
    use starknet::contract_address_const;
    use zeroable::Zeroable;
    
    #[storage]
    struct Storage {
        balances: LegacyMap<ContractAddress, u256>,
        allowances: LegacyMap<(ContractAddress, ContractAddress), u256>,
        total_supply: u256
    }

    #[constructor]
    fn constructor(ref self: ContractState, initial_supply: u256) {
        let caller = get_caller_address();
        self.balances.write(caller, initial_supply);
        self.total_supply.write(initial_supply);
    }

    #[external(v0)]
    impl IERC20Impl of super::IERC20<ContractState> {
        fn balanceOf(self: @ContractState, account: ContractAddress) -> u256 {
            self.balances.read(account)
        }

        fn transfer(ref self: ContractState, recipient: ContractAddress, amount: u256) -> bool {
            let sender = get_caller_address();
            self._transfer(sender, recipient, amount);
            true
        }

        fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool {
            let owner = get_caller_address();
            self.allowances.write((owner, spender), amount);
            true
        }

        fn transferFrom(
            ref self: ContractState, 
            sender: ContractAddress, 
            recipient: ContractAddress, 
            amount: u256
        ) -> bool {
            let caller = get_caller_address();
            let allowance = self.allowances.read((sender, caller));
            assert(allowance >= amount, 'ERC20: insufficient allowance');
            
            self.allowances.write((sender, caller), allowance - amount);
            self._transfer(sender, recipient, amount);
            true
        }
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {
        fn _transfer(
            ref self: ContractState,
            sender: ContractAddress,
            recipient: ContractAddress,
            amount: u256
        ) {
            assert(!sender.is_zero(), 'ERC20: transfer from zero');
            assert(!recipient.is_zero(), 'ERC20: transfer to zero');
            
            let sender_balance = self.balances.read(sender);
            assert(sender_balance >= amount, 'ERC20: insufficient balance');
            
            self.balances.write(sender, sender_balance - amount);
            let recipient_balance = self.balances.read(recipient);
            self.balances.write(recipient, recipient_balance + amount);
        }
    }
}