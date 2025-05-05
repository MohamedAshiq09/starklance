#[cfg(test)]
mod tests {
    use starknet::{ContractAddress, contract_address_const, get_caller_address, get_block_timestamp};
    use project::marketplace::FreelanceMarketplace::{
        ContractState, FreelanceMarketplaceImpl
    };
    use project::models::{Job, JobStatus};
    use snforge_std::{
        declare, ContractClassTrait, start_prank, stop_prank, CheatTarget, 
        start_warp, stop_warp, store_value, map_entry_address
    };
    use openzeppelin::token::erc20::interface::{
        IERC20, IERC20Dispatcher, IERC20DispatcherTrait
    };

    // Test constants
    const OWNER: felt252 = 'owner';
    const CLIENT: felt252 = 'client';
    const FREELANCER: felt252 = 'freelancer';
    const PLATFORM_FEE: u16 = 500; // 5%

    fn deploy_mock_erc20() -> ContractAddress {
        // You would need to implement this based on your testing needs
        // This would deploy a mock ERC20 token for testing
        contract_address_const::<'mock_token'>()
    }

    fn setup_marketplace() -> ContractAddress {
        let owner = contract_address_const::<OWNER>();
        let platform_wallet = owner;
        let mock_token = deploy_mock_erc20();
        
        // Declare and deploy the contract
        let contract_class = declare("FreelanceMarketplace");
        let constructor_args = array![
            owner.into(), 
            mock_token.into(), 
            PLATFORM_FEE.into(), 
            platform_wallet.into()
        ];
        let contract_address = contract_class.deploy(@constructor_args).unwrap();
        
        contract_address
    }

    #[test]
    fn test_contract_initialization() {
        let contract_address = setup_marketplace();
        
        // Verify platform fee is set correctly
        let platform_fee = FreelanceMarketplaceImpl::get_platform_fee(@ContractState { contract_address });
        assert(platform_fee == PLATFORM_FEE, 'Wrong platform fee');
        
        // Verify owner is set correctly
        let owner = FreelanceMarketplaceImpl::get_owner(@ContractState { contract_address });
        assert(owner == contract_address_const::<OWNER>(), 'Wrong owner');
    }

    #[test]
    #[should_panic(expected: ('Only owner can call',))]
    fn test_update_platform_fee_unauthorized() {
        let contract_address = setup_marketplace();
        let unauthorized_user = contract_address_const::<'unauthorized'>();
        
        // Try to update platform fee as unauthorized user
        start_prank(CheatTarget::One(contract_address), unauthorized_user);
        FreelanceMarketplaceImpl::update_platform_fee(
            ref ContractState { contract_address }, 
            600_u16
        );
        stop_prank(CheatTarget::One(contract_address));
    }

    // More tests would be added here
}