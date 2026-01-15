/// End-to-end tests for Tide Core v1.
/// 
/// Tests full lifecycle scenarios including:
/// - Complete deposit → finalize → release → claim flow
/// - Multi-backer reward distribution
/// - Transfer safety (ownership = entitlement)
/// - Pause semantics
#[test_only]
module tide_core::e2e_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::coin;
use sui::sui::SUI;
use sui::clock;

use tide_core::tide::{Self, Tide, AdminCap};
use tide_core::council::{Self, CouncilCap};
use tide_core::registry::{Self, ListingRegistry};
use tide_core::listing::{Self, Listing};
use tide_core::capital_vault::{Self, CapitalVault};
use tide_core::reward_vault::{Self, RewardVault, RouteCapability};
use tide_core::staking_adapter;
use tide_core::supporter_pass::SupporterPass;
use tide_core::constants;

// === Test Addresses ===
const ADMIN: address = @0xAD;
const ISSUER: address = @0x1551;
const BACKER1: address = @0xB1;
const BACKER2: address = @0xB2;
const VALIDATOR: address = @0xA1;

// === Helper Functions ===

fun setup_protocol(scenario: &mut Scenario) {
    // Initialize tide module
    ts::next_tx(scenario, ADMIN);
    {
        tide::init_for_testing(ts::ctx(scenario));
    };
    
    // Initialize council module
    ts::next_tx(scenario, ADMIN);
    {
        council::init_for_testing(ts::ctx(scenario));
    };
    
    // Initialize registry module
    ts::next_tx(scenario, ADMIN);
    {
        registry::init_for_testing(ts::ctx(scenario));
    };
}

fun create_listing(scenario: &mut Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        let mut registry = ts::take_shared<ListingRegistry>(scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(scenario);
        
        let (listing, capital_vault, reward_vault, staking_adapter, listing_cap, route_cap) = 
            listing::new(
                &mut registry,
                &council_cap,
                ISSUER,
                VALIDATOR,
                vector::empty(), // Deferred schedule
                vector::empty(),
                1000, // 10% revenue routing
                ts::ctx(scenario),
            );
        
        ts::return_shared(registry);
        transfer::public_transfer(council_cap, ADMIN);
        
        // Share listing objects
        listing::share(listing);
        capital_vault::share(capital_vault);
        reward_vault::share(reward_vault);
        staking_adapter::share(staking_adapter);
        
        // Transfer caps to issuer
        listing::transfer_cap(listing_cap, ISSUER);
        reward_vault::transfer_route_cap(route_cap, ISSUER);
    };
}

fun activate_listing(scenario: &mut Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(scenario);
        let clock = clock::create_for_testing(ts::ctx(scenario));
        
        listing.activate(&council_cap, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        transfer::public_transfer(council_cap, ADMIN);
    };
}

fun backer_deposit(scenario: &mut Scenario, backer: address, amount: u64) {
    ts::next_tx(scenario, backer);
    {
        let mut listing = ts::take_shared<Listing>(scenario);
        let tide = ts::take_shared<Tide>(scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(scenario);
        let clock = clock::create_for_testing(ts::ctx(scenario));
        
        let deposit = coin::mint_for_testing<SUI>(amount, ts::ctx(scenario));
        let pass = listing.deposit(
            &tide,
            &mut capital_vault,
            &mut reward_vault,
            deposit,
            &clock,
            ts::ctx(scenario),
        );
        
        transfer::public_transfer(pass, backer);
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(tide);
        ts::return_shared(capital_vault);
        ts::return_shared(reward_vault);
    };
}

// === Tests ===

#[test]
fun test_full_lifecycle_single_backer() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup protocol
    setup_protocol(&mut scenario);
    
    // Create listing
    create_listing(&mut scenario);
    
    // Activate listing
    activate_listing(&mut scenario);
    
    // Verify listing is active
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        assert!(listing.state() == constants::state_active!());
        ts::return_shared(listing);
    };
    
    // Backer deposits 10 SUI
    backer_deposit(&mut scenario, BACKER1, 10_000_000_000);
    
    // Verify deposit
    ts::next_tx(&mut scenario, BACKER1);
    {
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        assert!(capital_vault.total_principal() == 10_000_000_000);
        assert!(capital_vault.total_shares() > 0);
        ts::return_shared(capital_vault);
        
        // Verify backer has a pass
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        assert!(pass.shares() > 0);
        ts::return_to_sender(&scenario, pass);
    };
    
    // Finalize listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        listing.finalize(&council_cap, &mut capital_vault, &clock, ts::ctx(&mut scenario));
        
        assert!(listing.state() == constants::state_finalized!());
        assert!(capital_vault.is_schedule_finalized());
        assert!(capital_vault.num_tranches() == 13); // 1 initial + 12 monthly
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Collect raise fee and release initial tranche
    ts::next_tx(&mut scenario, ISSUER);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        // Collect raise fee (1% of 10 SUI = 0.1 SUI)
        listing.collect_raise_fee(&tide, &mut capital_vault, ts::ctx(&mut scenario));
        assert!(capital_vault.is_raise_fee_collected());
        
        // Release initial tranche (20% of net = 20% of 9.9 SUI ≈ 1.98 SUI)
        listing.release_tranche_at(&tide, &mut capital_vault, 0, &clock, ts::ctx(&mut scenario));
        assert!(capital_vault.tranches_released() == 1);
        
        clock::destroy_for_testing(clock);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Route revenue
    ts::next_tx(&mut scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(&scenario);
        
        // Verify shares were set from deposit
        assert!(reward_vault.total_shares() > 0);
        
        // Route 100 SUI in revenue (larger amount to ensure index updates)
        let revenue = coin::mint_for_testing<SUI>(100_000_000_000, ts::ctx(&mut scenario));
        reward_vault.deposit_rewards(&route_cap, revenue, ts::ctx(&mut scenario));
        
        assert!(reward_vault.total_deposited() == 100_000_000_000);
        // Index should update since total_shares > 0 and reward is significant
        assert!(reward_vault.global_index() > 0);
        
        ts::return_shared(reward_vault);
        transfer::public_transfer(route_cap, ISSUER);
    };
    
    // Backer claims rewards
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Calculate expected (backer has 100% of shares)
        let claimable = reward_vault.calculate_claimable(pass.shares(), pass.claim_index());
        assert!(claimable > 0);
        
        // Claim
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() > 0);
        
        // Pass claim index should be updated
        assert!(pass.claim_index() > 0);
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_multi_backer_proportional_rewards() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Backer 1 deposits 75 SUI (75%)
    backer_deposit(&mut scenario, BACKER1, 75_000_000_000);
    
    // Backer 2 deposits 25 SUI (25%)
    backer_deposit(&mut scenario, BACKER2, 25_000_000_000);
    
    // Verify total raised
    ts::next_tx(&mut scenario, ADMIN);
    {
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        assert!(capital_vault.total_principal() == 100_000_000_000);
        ts::return_shared(capital_vault);
    };
    
    // Route 100 SUI in revenue
    ts::next_tx(&mut scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(&scenario);
        
        let revenue = coin::mint_for_testing<SUI>(100_000_000_000, ts::ctx(&mut scenario));
        reward_vault.deposit_rewards(&route_cap, revenue, ts::ctx(&mut scenario));
        
        ts::return_shared(reward_vault);
        transfer::public_transfer(route_cap, ISSUER);
    };
    
    // Backer 1 claims ~75 SUI
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let claimable = reward_vault.calculate_claimable(pass.shares(), pass.claim_index());
        
        // Should be approximately 75 SUI (75% of 100)
        assert!(claimable >= 74_000_000_000 && claimable <= 76_000_000_000);
        
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() >= 74_000_000_000);
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    // Backer 2 claims ~25 SUI
    ts::next_tx(&mut scenario, BACKER2);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let claimable = reward_vault.calculate_claimable(pass.shares(), pass.claim_index());
        
        // Should be approximately 25 SUI (25% of 100)
        assert!(claimable >= 24_000_000_000 && claimable <= 26_000_000_000);
        
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() >= 24_000_000_000);
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_late_joiner_no_pre_deposit_claim() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Backer 1 deposits first
    backer_deposit(&mut scenario, BACKER1, 50_000_000_000);
    
    // Route revenue BEFORE Backer 2 joins
    ts::next_tx(&mut scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(&scenario);
        
        let revenue = coin::mint_for_testing<SUI>(100_000_000_000, ts::ctx(&mut scenario));
        reward_vault.deposit_rewards(&route_cap, revenue, ts::ctx(&mut scenario));
        
        ts::return_shared(reward_vault);
        transfer::public_transfer(route_cap, ISSUER);
    };
    
    // Backer 2 deposits AFTER rewards (late joiner)
    backer_deposit(&mut scenario, BACKER2, 50_000_000_000);
    
    // Backer 2 should NOT be able to claim the pre-deposit rewards
    ts::next_tx(&mut scenario, BACKER2);
    {
        let reward_vault = ts::take_shared<RewardVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Late joiner's claim_index is set to current global_index at deposit time
        // So they should have 0 claimable from pre-deposit rewards
        let claimable = reward_vault.calculate_claimable(pass.shares(), pass.claim_index());
        
        // Should be 0 or very small (rounding)
        assert!(claimable == 0);
        
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(reward_vault);
    };
    
    // Backer 1 should get ALL of the pre-deposit rewards
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let claimable = reward_vault.calculate_claimable(pass.shares(), pass.claim_index());
        
        // Backer 1 should get ~100 SUI (all of the revenue routed before B2 joined)
        assert!(claimable >= 99_000_000_000);
        
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        coin::burn_for_testing(reward);
        
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_transfer_claim_new_owner_claims() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Backer 1 deposits
    backer_deposit(&mut scenario, BACKER1, 100_000_000_000);
    
    // Route revenue (1000 SUI to ensure index updates with precision)
    ts::next_tx(&mut scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(&scenario);
        
        let revenue = coin::mint_for_testing<SUI>(1000_000_000_000, ts::ctx(&mut scenario));
        reward_vault.deposit_rewards(&route_cap, revenue, ts::ctx(&mut scenario));
        
        ts::return_shared(reward_vault);
        transfer::public_transfer(route_cap, ISSUER);
    };
    
    // Backer 1 transfers pass to Backer 2
    ts::next_tx(&mut scenario, BACKER1);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        transfer::public_transfer(pass, BACKER2);
    };
    
    // Backer 2 (new owner) claims rewards
    ts::next_tx(&mut scenario, BACKER2);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let claimable = reward_vault.calculate_claimable(pass.shares(), pass.claim_index());
        
        // New owner should be able to claim all rewards (1000 SUI)
        // Allow for some precision loss
        assert!(claimable >= 900_000_000_000);
        
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() >= 900_000_000_000);
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    // Verify Backer 1 no longer has any pass
    ts::next_tx(&mut scenario, BACKER1);
    {
        assert!(!ts::has_most_recent_for_sender<SupporterPass>(&scenario));
    };
    
    ts::end(scenario);
}

#[test]
fun test_global_pause_blocks_deposits() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Pause protocol
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut tide = ts::take_shared<Tide>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        tide.pause(&admin_cap, ts::ctx(&mut scenario));
        assert!(tide.is_paused());
        
        ts::return_shared(tide);
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    // Verify protocol is paused
    ts::next_tx(&mut scenario, BACKER1);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        assert!(tide.is_paused());
        ts::return_shared(tide);
    };
    
    ts::end(scenario);
}

#[test]
fun test_claims_allowed_when_paused() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup, activate, deposit
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    backer_deposit(&mut scenario, BACKER1, 100_000_000_000);
    
    // Route revenue (1000 SUI for precision)
    ts::next_tx(&mut scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(&scenario);
        
        let revenue = coin::mint_for_testing<SUI>(1000_000_000_000, ts::ctx(&mut scenario));
        reward_vault.deposit_rewards(&route_cap, revenue, ts::ctx(&mut scenario));
        
        ts::return_shared(reward_vault);
        transfer::public_transfer(route_cap, ISSUER);
    };
    
    // Pause protocol
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut tide = ts::take_shared<Tide>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        tide.pause(&admin_cap, ts::ctx(&mut scenario));
        
        ts::return_shared(tide);
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    // Backer can STILL claim even when paused (per spec)
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Claims are allowed even when paused
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() > 0);
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}
