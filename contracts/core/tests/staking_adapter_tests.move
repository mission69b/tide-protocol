/// Unit tests for StakingAdapter module.
/// 
/// Tests core staking adapter functionality without SuiSystemState.
/// Note: stake/unstake operations require SuiSystemState and are tested 
/// in integration tests or manually on testnet.
#[test_only]
module tide_core::staking_adapter_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::coin;
use sui::sui::SUI;

use tide_core::staking_adapter::{Self, StakingAdapter};
use tide_core::constants;

// === Test Addresses ===
const ADMIN: address = @0xAD;
const VALIDATOR1: address = @0xA1;
const VALIDATOR2: address = @0xA2;

// === Constants ===
const ONE_SUI: u64 = 1_000_000_000;
const TEN_SUI: u64 = 10_000_000_000;
const HUNDRED_SUI: u64 = 100_000_000_000;

// === Helper Functions ===

fun create_test_adapter(scenario: &mut Scenario): StakingAdapter {
    let listing_id = object::id_from_address(@0x123);
    staking_adapter::new_for_testing(listing_id, VALIDATOR1, ts::ctx(scenario))
}

// === Constructor Tests ===

#[test]
fun test_new_adapter() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing_id = object::id_from_address(@0x123);
        let adapter = staking_adapter::new_for_testing(listing_id, VALIDATOR1, ts::ctx(&mut scenario));
        
        // Verify initial state
        assert!(adapter.listing_id() == listing_id);
        assert!(adapter.validator() == VALIDATOR1);
        assert!(adapter.pending_balance() == 0);
        assert!(adapter.staked_principal() == 0);
        assert!(adapter.stake_count() == 0);
        assert!(adapter.total_rewards_collected() == 0);
        assert!(adapter.is_enabled());
        assert!(adapter.total_capital() == 0);
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

// === Deposit Tests ===

#[test]
fun test_deposit() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // Deposit 10 SUI
        let coin = coin::mint_for_testing<SUI>(TEN_SUI, ts::ctx(&mut scenario));
        staking_adapter::deposit(&mut adapter, coin);
        
        assert!(adapter.pending_balance() == TEN_SUI);
        assert!(adapter.total_capital() == TEN_SUI);
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit_multiple() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // First deposit
        let coin1 = coin::mint_for_testing<SUI>(TEN_SUI, ts::ctx(&mut scenario));
        staking_adapter::deposit(&mut adapter, coin1);
        
        // Second deposit
        let coin2 = coin::mint_for_testing<SUI>(TEN_SUI, ts::ctx(&mut scenario));
        staking_adapter::deposit(&mut adapter, coin2);
        
        assert!(adapter.pending_balance() == TEN_SUI * 2);
        assert!(adapter.total_capital() == TEN_SUI * 2);
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
fun test_deposit_for_testing_helper() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // Use the testing helper
        staking_adapter::deposit_for_testing(&mut adapter, TEN_SUI, ts::ctx(&mut scenario));
        
        assert!(adapter.pending_balance() == TEN_SUI);
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

// === Withdraw Tests ===

#[test]
fun test_withdraw() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // Deposit 10 SUI
        staking_adapter::deposit_for_testing(&mut adapter, TEN_SUI, ts::ctx(&mut scenario));
        
        // Withdraw 5 SUI
        let withdrawn = staking_adapter::withdraw(&mut adapter, TEN_SUI / 2, ts::ctx(&mut scenario));
        
        assert!(withdrawn.value() == TEN_SUI / 2);
        assert!(adapter.pending_balance() == TEN_SUI / 2);
        
        coin::burn_for_testing(withdrawn);
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
fun test_withdraw_full_amount() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // Deposit 10 SUI
        staking_adapter::deposit_for_testing(&mut adapter, TEN_SUI, ts::ctx(&mut scenario));
        
        // Withdraw all
        let withdrawn = staking_adapter::withdraw(&mut adapter, TEN_SUI, ts::ctx(&mut scenario));
        
        assert!(withdrawn.value() == TEN_SUI);
        assert!(adapter.pending_balance() == 0);
        
        coin::burn_for_testing(withdrawn);
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 8, location = tide_core::staking_adapter)]
fun test_withdraw_insufficient_balance() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // Deposit 10 SUI
        staking_adapter::deposit_for_testing(&mut adapter, TEN_SUI, ts::ctx(&mut scenario));
        
        // Try to withdraw more than available
        let withdrawn = staking_adapter::withdraw(&mut adapter, TEN_SUI + 1, ts::ctx(&mut scenario));
        
        coin::burn_for_testing(withdrawn);
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

// === Enable/Disable Tests ===

#[test]
fun test_set_enabled() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // Enabled by default
        assert!(adapter.is_enabled());
        
        // Disable
        staking_adapter::set_enabled(&mut adapter, false);
        assert!(!adapter.is_enabled());
        
        // Re-enable
        staking_adapter::set_enabled(&mut adapter, true);
        assert!(adapter.is_enabled());
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

// === Validator Update Tests ===

#[test]
fun test_set_validator() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        assert!(adapter.validator() == VALIDATOR1);
        
        staking_adapter::set_validator(&mut adapter, VALIDATOR2);
        
        assert!(adapter.validator() == VALIDATOR2);
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

// === Reward Split Calculation Tests ===

#[test]
fun test_calculate_reward_split_basic() {
    // 100 SUI rewards -> 80 backer, 20 treasury (80/20 split)
    let (backer, treasury) = staking_adapter::calculate_reward_split(HUNDRED_SUI);
    
    let expected_backer = (HUNDRED_SUI * constants::staking_backer_bps!()) / constants::max_bps!();
    let expected_treasury = HUNDRED_SUI - expected_backer;
    
    assert!(backer == expected_backer);
    assert!(treasury == expected_treasury);
    
    // Verify 80/20 split
    assert!(backer == 80_000_000_000); // 80 SUI
    assert!(treasury == 20_000_000_000); // 20 SUI
}

#[test]
fun test_calculate_reward_split_zero() {
    let (backer, treasury) = staking_adapter::calculate_reward_split(0);
    
    assert!(backer == 0);
    assert!(treasury == 0);
}

#[test]
fun test_calculate_reward_split_small_amount() {
    // 100 (smallest divisible amount for 80/20)
    let (backer, treasury) = staking_adapter::calculate_reward_split(100);
    
    assert!(backer == 80);
    assert!(treasury == 20);
}

#[test]
fun test_calculate_reward_split_one_sui() {
    // 1 SUI = 1_000_000_000
    let (backer, treasury) = staking_adapter::calculate_reward_split(ONE_SUI);
    
    // 80% of 1 SUI = 800_000_000
    assert!(backer == 800_000_000);
    assert!(treasury == 200_000_000);
}

#[test]
fun test_calculate_reward_split_sum_equals_total() {
    // Test various amounts to ensure backer + treasury == total
    let amounts = vector[1, 10, 100, 1000, ONE_SUI, TEN_SUI, HUNDRED_SUI, 999_999_999];
    let mut i = 0;
    while (i < amounts.length()) {
        let amount = amounts[i];
        let (backer, treasury) = staking_adapter::calculate_reward_split(amount);
        assert!(backer + treasury == amount);
        i = i + 1;
    };
}

// === Split Rewards Tests ===

#[test]
fun test_split_rewards() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let adapter = create_test_adapter(&mut scenario);
        
        // Create 100 SUI rewards coin
        let rewards = coin::mint_for_testing<SUI>(HUNDRED_SUI, ts::ctx(&mut scenario));
        
        let (backer_coin, treasury_coin) = staking_adapter::split_rewards(
            &adapter,
            rewards,
            ts::ctx(&mut scenario),
        );
        
        assert!(backer_coin.value() == 80_000_000_000); // 80%
        assert!(treasury_coin.value() == 20_000_000_000); // 20%
        
        coin::burn_for_testing(backer_coin);
        coin::burn_for_testing(treasury_coin);
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
fun test_split_rewards_zero() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let adapter = create_test_adapter(&mut scenario);
        
        // Zero rewards
        let rewards = coin::mint_for_testing<SUI>(0, ts::ctx(&mut scenario));
        
        let (backer_coin, treasury_coin) = staking_adapter::split_rewards(
            &adapter,
            rewards,
            ts::ctx(&mut scenario),
        );
        
        assert!(backer_coin.value() == 0);
        assert!(treasury_coin.value() == 0);
        
        coin::burn_for_testing(backer_coin);
        coin::burn_for_testing(treasury_coin);
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

// === View Function Tests ===

#[test]
fun test_view_functions() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // Deposit some funds
        staking_adapter::deposit_for_testing(&mut adapter, TEN_SUI, ts::ctx(&mut scenario));
        
        // Test all view functions
        assert!(adapter.pending_balance() == TEN_SUI);
        assert!(adapter.staked_principal() == 0); // Not staked yet
        assert!(adapter.stake_count() == 0);
        assert!(adapter.total_rewards_collected() == 0);
        assert!(adapter.validator() == VALIDATOR1);
        assert!(adapter.is_enabled());
        assert!(adapter.total_capital() == TEN_SUI);
        
        // Legacy functions
        assert!(adapter.staked_amount() == 0);
        assert!(adapter.pending_unstake() == 0);
        assert!(adapter.calculate_accumulated_rewards() == 0);
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
fun test_has_stake_at() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let adapter = create_test_adapter(&mut scenario);
        
        // No stakes exist
        assert!(!adapter.has_stake_at(0));
        assert!(!adapter.has_stake_at(1));
        assert!(!adapter.has_stake_at(999));
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

// === Legacy Function Tests ===

#[test]
fun test_legacy_request_unstake() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // This should be a no-op
        staking_adapter::request_unstake(&mut adapter, ONE_SUI);
        
        // Nothing should change
        assert!(adapter.pending_unstake() == 0);
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
fun test_legacy_process_unstake() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // This should be a no-op
        staking_adapter::process_unstake(&mut adapter, ts::ctx(&mut scenario));
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}

#[test]
fun test_legacy_collect_rewards() {
    let mut scenario = ts::begin(ADMIN);
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut adapter = create_test_adapter(&mut scenario);
        
        // This returns None
        let rewards = staking_adapter::collect_rewards(&mut adapter, ts::ctx(&mut scenario));
        assert!(rewards.is_none());
        rewards.destroy_none();
        
        staking_adapter::destroy_for_testing(adapter);
    };
    ts::end(scenario);
}
