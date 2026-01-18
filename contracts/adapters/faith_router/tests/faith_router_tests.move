/// Unit tests for faith_router adapter.
#[test_only]
module faith_router::faith_router_tests;

use sui::coin;
use sui::sui::SUI;
use sui::test_scenario::{Self, Scenario};

use tide_core::reward_vault::{Self, RewardVault, RouteCapability};

use faith_router::faith_router;

// === Test Constants ===

const DEPLOYER: address = @0xDE9;
const FAITH_ADMIN: address = @0xFA17;

// === Helper Functions ===

fun setup_test(): Scenario {
    test_scenario::begin(DEPLOYER)
}

fun create_route_cap(scenario: &mut Scenario): RouteCapability {
    let listing_id = object::id_from_address(@0x1);
    let ctx = scenario.ctx();
    reward_vault::create_route_cap_for_testing(listing_id, ctx)
}

fun create_reward_vault(scenario: &mut Scenario): RewardVault {
    let listing_id = object::id_from_address(@0x1);
    let ctx = scenario.ctx();
    let mut vault = reward_vault::new_for_testing(listing_id, ctx);
    // Set some shares so reward index updates work
    vault.set_total_shares_for_testing(1_000_000_000_000); // 1000 SUI worth
    vault
}

// === Constructor Tests ===

#[test]
fun test_new_router() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        let listing_id = route_cap.route_cap_listing_id();
        
        let (router, cap) = faith_router::new_for_testing(
            route_cap,
            1000, // 10% revenue
            scenario.ctx(),
        );
        
        // Verify router properties
        assert!(router.listing_id() == listing_id);
        assert!(router.revenue_bps() == 1000);
        assert!(router.total_routed() == 0);
        assert!(router.version() == faith_router::current_version());
        
        // Cleanup
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
    };
    
    scenario.end();
}

#[test]
#[expected_failure(abort_code = faith_router::EInvalidBps)]
fun test_new_router_invalid_bps() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        
        // Try to create with bps > 10000 (100%)
        let (router, cap) = faith_router::new_for_testing(
            route_cap,
            15000, // 150% - invalid
            scenario.ctx(),
        );
        
        // Won't reach here
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
    };
    
    scenario.end();
}

// === Calculate Revenue Tests ===

#[test]
fun test_calculate_revenue() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        
        let (router, cap) = faith_router::new_for_testing(
            route_cap,
            1000, // 10%
            scenario.ctx(),
        );
        
        // 10% of 100 SUI = 10 SUI
        let revenue = router.calculate_revenue(100_000_000_000); // 100 SUI
        assert!(revenue == 10_000_000_000); // 10 SUI
        
        // 10% of 1 SUI = 0.1 SUI
        let small_revenue = router.calculate_revenue(1_000_000_000); // 1 SUI
        assert!(small_revenue == 100_000_000); // 0.1 SUI
        
        // 10% of 0 = 0
        let zero_revenue = router.calculate_revenue(0);
        assert!(zero_revenue == 0);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
    };
    
    scenario.end();
}

#[test]
fun test_calculate_revenue_different_bps() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        
        // 5% revenue share
        let (router, cap) = faith_router::new_for_testing(
            route_cap,
            500, // 5%
            scenario.ctx(),
        );
        
        // 5% of 200 SUI = 10 SUI
        let revenue = router.calculate_revenue(200_000_000_000);
        assert!(revenue == 10_000_000_000);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
    };
    
    scenario.end();
}

// === Route Tests ===

#[test]
fun test_route_updates_total() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        let mut vault = create_reward_vault(&mut scenario);
        
        let (mut router, cap) = faith_router::new_for_testing(
            route_cap,
            1000,
            scenario.ctx(),
        );
        
        // Route 5 SUI
        let coin = coin::mint_for_testing<SUI>(5_000_000_000, scenario.ctx());
        router.route(&mut vault, coin, scenario.ctx());
        
        assert!(router.total_routed() == 5_000_000_000);
        assert!(vault.balance() == 5_000_000_000);
        
        // Route another 3 SUI
        let coin2 = coin::mint_for_testing<SUI>(3_000_000_000, scenario.ctx());
        router.route(&mut vault, coin2, scenario.ctx());
        
        assert!(router.total_routed() == 8_000_000_000);
        assert!(vault.balance() == 8_000_000_000);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
        reward_vault::destroy_with_balance_for_testing(vault);
    };
    
    scenario.end();
}

#[test]
#[expected_failure(abort_code = faith_router::EZeroAmount)]
fun test_route_zero_amount_fails() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        let mut vault = create_reward_vault(&mut scenario);
        
        let (mut router, cap) = faith_router::new_for_testing(
            route_cap,
            1000,
            scenario.ctx(),
        );
        
        // Try to route 0 SUI
        let coin = coin::mint_for_testing<SUI>(0, scenario.ctx());
        router.route(&mut vault, coin, scenario.ctx());
        
        // Won't reach here
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
        reward_vault::destroy_for_testing(vault);
    };
    
    scenario.end();
}

// === View Function Tests ===

#[test]
fun test_view_functions() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        let listing_id = route_cap.route_cap_listing_id();
        
        let (router, cap) = faith_router::new_for_testing(
            route_cap,
            2500, // 25%
            scenario.ctx(),
        );
        
        // Test all view functions
        assert!(router.version() == 1);
        assert!(router.listing_id() == listing_id);
        assert!(router.revenue_bps() == 2500);
        assert!(router.total_routed() == 0);
        assert!(faith_router::current_version() == 1);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
    };
    
    scenario.end();
}

// === Integration Test: Full Flow ===

#[test]
fun test_full_routing_flow() {
    let mut scenario = setup_test();
    
    // Deploy router
    scenario.next_tx(FAITH_ADMIN);
    {
        let route_cap = create_route_cap(&mut scenario);
        let mut vault = create_reward_vault(&mut scenario);
        
        let (mut router, cap) = faith_router::new_for_testing(
            route_cap,
            1000, // 10%
            scenario.ctx(),
        );
        
        // Simulate: FAITH collects 100 SUI in fees
        let total_fees = 100_000_000_000u64; // 100 SUI
        
        // Calculate 10% for Tide
        let tide_share = router.calculate_revenue(total_fees);
        assert!(tide_share == 10_000_000_000); // 10 SUI
        
        // Route the revenue
        let revenue_coin = coin::mint_for_testing<SUI>(tide_share, scenario.ctx());
        router.route(&mut vault, revenue_coin, scenario.ctx());
        
        // Verify
        assert!(router.total_routed() == 10_000_000_000);
        assert!(vault.balance() == 10_000_000_000);
        assert!(vault.global_index() > 0); // Index updated
        
        // Cleanup
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
        reward_vault::destroy_with_balance_for_testing(vault);
    };
    
    scenario.end();
}

// === Edge Cases ===

#[test]
fun test_route_minimum_amount() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        let mut vault = create_reward_vault(&mut scenario);
        
        let (mut router, cap) = faith_router::new_for_testing(
            route_cap,
            1000,
            scenario.ctx(),
        );
        
        // Route 1 MIST (minimum possible)
        let coin = coin::mint_for_testing<SUI>(1, scenario.ctx());
        router.route(&mut vault, coin, scenario.ctx());
        
        assert!(router.total_routed() == 1);
        assert!(vault.balance() == 1);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
        reward_vault::destroy_with_balance_for_testing(vault);
    };
    
    scenario.end();
}

#[test]
fun test_route_large_amount() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        let mut vault = create_reward_vault(&mut scenario);
        
        let (mut router, cap) = faith_router::new_for_testing(
            route_cap,
            1000,
            scenario.ctx(),
        );
        
        // Route 1 million SUI
        let large_amount = 1_000_000_000_000_000u64; // 1M SUI
        let coin = coin::mint_for_testing<SUI>(large_amount, scenario.ctx());
        router.route(&mut vault, coin, scenario.ctx());
        
        assert!(router.total_routed() == large_amount);
        assert!(vault.balance() == large_amount);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
        reward_vault::destroy_with_balance_for_testing(vault);
    };
    
    scenario.end();
}

#[test]
fun test_max_bps() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        
        // 100% revenue share (max)
        let (router, cap) = faith_router::new_for_testing(
            route_cap,
            10000, // 100%
            scenario.ctx(),
        );
        
        // 100% of 50 SUI = 50 SUI
        let revenue = router.calculate_revenue(50_000_000_000);
        assert!(revenue == 50_000_000_000);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
    };
    
    scenario.end();
}

#[test]
fun test_zero_bps() {
    let mut scenario = setup_test();
    
    scenario.next_tx(DEPLOYER);
    {
        let route_cap = create_route_cap(&mut scenario);
        
        // 0% revenue share (edge case)
        let (router, cap) = faith_router::new_for_testing(
            route_cap,
            0, // 0%
            scenario.ctx(),
        );
        
        // 0% of anything = 0
        let revenue = router.calculate_revenue(100_000_000_000);
        assert!(revenue == 0);
        
        faith_router::destroy_for_testing(router);
        faith_router::destroy_cap_for_testing(cap);
    };
    
    scenario.end();
}
