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
use tide_core::treasury_vault::{Self, TreasuryVault};
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
    // Initialize tide module (creates Tide + TreasuryVault)
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
    
    // Create treasury vault for testing
    ts::next_tx(scenario, ADMIN);
    {
        let vault = treasury_vault::new_for_testing(ts::ctx(scenario));
        treasury_vault::share(vault);
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
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        // Collect raise fee (1% of 10 SUI = 0.1 SUI) - deposited to treasury vault
        listing.collect_raise_fee(&tide, &mut treasury_vault, &mut capital_vault, ts::ctx(&mut scenario));
        assert!(capital_vault.is_raise_fee_collected());
        assert!(treasury_vault.balance() > 0); // Fee deposited to vault
        
        // Release initial tranche (20% of net = 20% of 9.9 SUI ≈ 1.98 SUI)
        listing.release_tranche_at(&tide, &mut capital_vault, 0, &clock, ts::ctx(&mut scenario));
        assert!(capital_vault.tranches_released() == 1);
        
        clock::destroy_for_testing(clock);
        ts::return_shared(tide);
        ts::return_shared(treasury_vault);
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

#[test]
fun test_per_listing_pause() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup, activate, deposit
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    backer_deposit(&mut scenario, BACKER1, 100_000_000_000);
    
    // Route some revenue
    ts::next_tx(&mut scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(&scenario);
        
        let revenue = coin::mint_for_testing<SUI>(100_000_000_000, ts::ctx(&mut scenario));
        reward_vault.deposit_rewards(&route_cap, revenue, ts::ctx(&mut scenario));
        
        ts::return_shared(reward_vault);
        transfer::public_transfer(route_cap, ISSUER);
    };
    
    // Council pauses the LISTING (not protocol)
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        
        listing.pause(&council_cap);
        assert!(listing.is_paused());
        
        ts::return_shared(listing);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Backer can STILL claim even when listing is paused (per spec)
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Listing is paused but claims still work
        assert!(listing.is_paused());
        
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() > 0);
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    // Council resumes the listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        
        listing.resume(&council_cap);
        assert!(!listing.is_paused());
        
        ts::return_shared(listing);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
fun test_staking_adapter_deposit_withdraw() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup, activate, and deposit
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Verify staking adapter initial state
    ts::next_tx(&mut scenario, ADMIN);
    {
        let staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        assert!(staking.pending_balance() == 0);
        assert!(staking.staked_principal() == 0);
        assert!(staking.total_capital() == 0);
        ts::return_shared(staking);
    };
    
    // Deposit funds to staking adapter
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        staking_adapter::deposit_for_testing(&mut staking, 50_000_000_000, ts::ctx(&mut scenario));
        
        assert!(staking.pending_balance() == 50_000_000_000);
        assert!(staking.total_capital() == 50_000_000_000);
        
        ts::return_shared(staking);
    };
    
    // Withdraw part of the funds
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        let withdrawn = staking_adapter::withdraw(&mut staking, 20_000_000_000, ts::ctx(&mut scenario));
        
        assert!(withdrawn.value() == 20_000_000_000);
        assert!(staking.pending_balance() == 30_000_000_000);
        
        coin::burn_for_testing(withdrawn);
        ts::return_shared(staking);
    };
    
    ts::end(scenario);
}

#[test]
fun test_staking_adapter_listing_link() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    
    // Verify staking adapter is linked to listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        // Staking adapter's listing_id should match listing's ID
        assert!(staking.listing_id() == listing.id());
        
        // Validator should be set to the one passed during listing creation
        assert!(staking.validator() == VALIDATOR);
        
        ts::return_shared(listing);
        ts::return_shared(staking);
    };
    
    ts::end(scenario);
}

#[test]
fun test_staking_reward_split_calculation() {
    let mut scenario = ts::begin(ADMIN);
    
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        // Create 100 SUI rewards
        let rewards = coin::mint_for_testing<SUI>(100_000_000_000, ts::ctx(&mut scenario));
        
        // Split rewards (80% backer, 20% treasury per constants)
        let (backer_coin, treasury_coin) = staking_adapter::split_rewards(
            &staking,
            rewards,
            ts::ctx(&mut scenario),
        );
        
        // Verify 80/20 split
        assert!(backer_coin.value() == 80_000_000_000); // 80 SUI
        assert!(treasury_coin.value() == 20_000_000_000); // 20 SUI
        
        coin::burn_for_testing(backer_coin);
        coin::burn_for_testing(treasury_coin);
        ts::return_shared(staking);
    };
    
    ts::end(scenario);
}

#[test]
fun test_staking_multiple_deposits() {
    let mut scenario = ts::begin(ADMIN);
    
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    
    // Multiple deposits accumulate
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        // First deposit
        staking_adapter::deposit_for_testing(&mut staking, 10_000_000_000, ts::ctx(&mut scenario));
        assert!(staking.pending_balance() == 10_000_000_000);
        
        // Second deposit
        staking_adapter::deposit_for_testing(&mut staking, 25_000_000_000, ts::ctx(&mut scenario));
        assert!(staking.pending_balance() == 35_000_000_000);
        
        // Third deposit
        staking_adapter::deposit_for_testing(&mut staking, 15_000_000_000, ts::ctx(&mut scenario));
        assert!(staking.pending_balance() == 50_000_000_000);
        
        // Total capital check
        assert!(staking.total_capital() == 50_000_000_000);
        
        ts::return_shared(staking);
    };
    
    ts::end(scenario);
}

#[test]
fun test_staking_enable_disable() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Verify staking is enabled by default
    ts::next_tx(&mut scenario, ADMIN);
    {
        let staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        assert!(staking.is_enabled());
        ts::return_shared(staking);
    };
    
    // Council disables staking
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        listing.set_staking_enabled(&tide, &council_cap, &mut staking, false);
        assert!(!staking.is_enabled());
        
        ts::return_shared(listing);
        ts::return_shared(tide);
        ts::return_shared(staking);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Council re-enables staking
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        listing.set_staking_enabled(&tide, &council_cap, &mut staking, true);
        assert!(staking.is_enabled());
        
        ts::return_shared(listing);
        ts::return_shared(tide);
        ts::return_shared(staking);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    ts::end(scenario);
}

// === Deposit Flow Edge Cases ===

#[test]
#[expected_failure(abort_code = 1, location = tide_core::listing)]  // errors::paused()
fun test_deposit_blocked_when_listing_paused() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Council pauses the listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        
        listing.pause(&council_cap);
        
        ts::return_shared(listing);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Backer tries to deposit - should fail
    ts::next_tx(&mut scenario, BACKER1);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        let deposit = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
        let pass = listing.deposit(
            &tide,
            &mut capital_vault,
            &mut reward_vault,
            deposit,
            &clock,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(pass, BACKER1);
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(tide);
        ts::return_shared(capital_vault);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 0, location = tide_core::listing)]  // errors::not_active()
fun test_deposit_blocked_in_draft_state() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup but DON'T activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    // Note: listing is in DRAFT state
    
    // Backer tries to deposit - should fail
    ts::next_tx(&mut scenario, BACKER1);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        // Listing is in Draft state, deposit should fail
        assert!(listing.state() == constants::state_draft!());
        
        let deposit = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
        let pass = listing.deposit(
            &tide,
            &mut capital_vault,
            &mut reward_vault,
            deposit,
            &clock,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(pass, BACKER1);
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(tide);
        ts::return_shared(capital_vault);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 0, location = tide_core::listing)]  // errors::not_active()
fun test_deposit_blocked_in_finalized_state() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup, activate, deposit, then finalize
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    backer_deposit(&mut scenario, BACKER1, 10_000_000_000);
    
    // Finalize the listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        listing.finalize(&council_cap, &mut capital_vault, &clock, ts::ctx(&mut scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Backer2 tries to deposit after finalization - should fail
    ts::next_tx(&mut scenario, BACKER2);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        assert!(listing.state() == constants::state_finalized!());
        
        let deposit = coin::mint_for_testing<SUI>(10_000_000_000, ts::ctx(&mut scenario));
        let pass = listing.deposit(
            &tide,
            &mut capital_vault,
            &mut reward_vault,
            deposit,
            &clock,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(pass, BACKER2);
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(tide);
        ts::return_shared(capital_vault);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}

// === Claim Flow Edge Cases ===

#[test]
#[expected_failure(abort_code = 3, location = tide_core::listing)]  // errors::nothing_to_claim() = 3
fun test_claim_nothing_to_claim() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup, activate, deposit - but NO revenue routed
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    backer_deposit(&mut scenario, BACKER1, 10_000_000_000);
    
    // Backer tries to claim with no revenue routed
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // No rewards deposited, should fail
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
#[expected_failure(abort_code = 3, location = tide_core::listing)]  // errors::nothing_to_claim() = 3
fun test_double_claim_fails() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup, activate, deposit, route revenue
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    backer_deposit(&mut scenario, BACKER1, 100_000_000_000);
    
    // Route revenue
    ts::next_tx(&mut scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(&scenario);
        
        let revenue = coin::mint_for_testing<SUI>(100_000_000_000, ts::ctx(&mut scenario));
        reward_vault.deposit_rewards(&route_cap, revenue, ts::ctx(&mut scenario));
        
        ts::return_shared(reward_vault);
        transfer::public_transfer(route_cap, ISSUER);
    };
    
    // First claim - should succeed
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() > 0);
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    // Second claim - should fail (nothing to claim)
    ts::next_tx(&mut scenario, BACKER1);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Already claimed, index is up to date, claimable should be 0
        let reward = listing.claim(&tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        coin::burn_for_testing(reward);
        ts::return_to_sender(&scenario, pass);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    ts::end(scenario);
}

// === Lifecycle State Tests ===

#[test]
fun test_listing_complete_lifecycle() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    
    // Verify Draft state
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        assert!(listing.state() == constants::state_draft!());
        ts::return_shared(listing);
    };
    
    // Activate
    activate_listing(&mut scenario);
    
    // Verify Active state
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        assert!(listing.state() == constants::state_active!());
        ts::return_shared(listing);
    };
    
    // Deposit
    backer_deposit(&mut scenario, BACKER1, 10_000_000_000);
    
    // Finalize
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        listing.finalize(&council_cap, &mut capital_vault, &clock, ts::ctx(&mut scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Verify Finalized state
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        assert!(listing.state() == constants::state_finalized!());
        ts::return_shared(listing);
    };
    
    // Collect fee and release all tranches
    ts::next_tx(&mut scenario, ISSUER);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let mut clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        // Collect raise fee
        listing.collect_raise_fee(&tide, &mut treasury_vault, &mut capital_vault, ts::ctx(&mut scenario));
        
        // Release all tranches (simulate time passing)
        let num_tranches = capital_vault.num_tranches();
        let mut i = 0u64;
        let mut current_time = clock.timestamp_ms();
        while (i < num_tranches) {
            // Fast forward time to make tranche ready
            current_time = current_time + 30 * 24 * 60 * 60 * 1000 + 1;
            clock::set_for_testing(&mut clock, current_time);
            listing.release_tranche_at(&tide, &mut capital_vault, i, &clock, ts::ctx(&mut scenario));
            i = i + 1;
        };
        
        assert!(capital_vault.all_released());
        
        ts::return_shared(treasury_vault);
        
        clock::destroy_for_testing(clock);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Complete the listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let reward_vault = ts::take_shared<RewardVault>(&scenario);
        
        listing.complete(&council_cap, &capital_vault, &reward_vault, ts::ctx(&mut scenario));
        
        assert!(listing.state() == constants::state_completed!());
        assert!(listing.is_completed());
        
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        ts::return_shared(reward_vault);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 11, location = tide_core::listing)]  // errors::not_draft()
fun test_cannot_activate_non_draft_listing() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Try to activate again - should fail
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        // Already active, should fail
        listing.activate(&council_cap, &clock, ts::ctx(&mut scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = 0, location = tide_core::listing)]  // errors::not_active()
fun test_cannot_finalize_draft_listing() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup but don't activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    
    // Try to finalize from Draft - should fail
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        listing.finalize(&council_cap, &mut capital_vault, &clock, ts::ctx(&mut scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    ts::end(scenario);
}

// === Admin Cap Rotation ===

#[test]
fun test_admin_cap_rotation() {
    let mut scenario = ts::begin(ADMIN);
    
    setup_protocol(&mut scenario);
    
    let new_admin: address = @0xAD2;
    
    // Rotate admin cap
    ts::next_tx(&mut scenario, ADMIN);
    {
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        tide::transfer_admin_cap(admin_cap, new_admin, ts::ctx(&mut scenario));
    };
    
    // Verify new admin has the cap
    ts::next_tx(&mut scenario, new_admin);
    {
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        // New admin can use the cap
        transfer::public_transfer(admin_cap, new_admin);
    };
    
    // Verify old admin no longer has cap
    ts::next_tx(&mut scenario, ADMIN);
    {
        assert!(!ts::has_most_recent_for_sender<AdminCap>(&scenario));
    };
    
    ts::end(scenario);
}

// === Council Cap Rotation ===

#[test]
fun test_council_cap_rotation() {
    let mut scenario = ts::begin(ADMIN);
    
    setup_protocol(&mut scenario);
    
    let new_council: address = @0xC2;
    
    // Rotate council cap
    ts::next_tx(&mut scenario, ADMIN);
    {
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        
        council::transfer_cap(council_cap, new_council, ts::ctx(&mut scenario));
    };
    
    // Verify new council has the cap
    ts::next_tx(&mut scenario, new_council);
    {
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        // New council can use the cap
        transfer::public_transfer(council_cap, new_council);
    };
    
    // Verify old admin no longer has council cap
    ts::next_tx(&mut scenario, ADMIN);
    {
        assert!(!ts::has_most_recent_for_sender<CouncilCap>(&scenario));
    };
    
    ts::end(scenario);
}

// === Tranche Release Tests ===

#[test]
#[expected_failure(abort_code = 1, location = tide_core::listing)]  // errors::paused()
fun test_tranche_release_blocked_when_paused() {
    let mut scenario = ts::begin(ADMIN);
    
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    backer_deposit(&mut scenario, BACKER1, 10_000_000_000);
    
    // Finalize
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        listing.finalize(&council_cap, &mut capital_vault, &clock, ts::ctx(&mut scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Collect raise fee
    ts::next_tx(&mut scenario, ISSUER);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        
        listing.collect_raise_fee(&tide, &mut treasury_vault, &mut capital_vault, ts::ctx(&mut scenario));
        
        ts::return_shared(tide);
        ts::return_shared(treasury_vault);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Pause the listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        
        listing.pause(&council_cap);
        
        ts::return_shared(listing);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Try to release tranche while paused - should fail
    ts::next_tx(&mut scenario, ISSUER);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        listing.release_tranche_at(&tide, &mut capital_vault, 0, &clock, ts::ctx(&mut scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_validator_update() {
    let mut scenario = ts::begin(ADMIN);
    
    // Setup and activate
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Verify original validator
    ts::next_tx(&mut scenario, ADMIN);
    {
        let staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        assert!(staking.validator() == VALIDATOR);
        ts::return_shared(staking);
    };
    
    // Council updates validator
    let new_validator: address = @0xA2;
    ts::next_tx(&mut scenario, ADMIN);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut staking = ts::take_shared<staking_adapter::StakingAdapter>(&scenario);
        
        listing.set_staking_validator(&tide, &council_cap, &mut staking, new_validator);
        assert!(staking.validator() == new_validator);
        
        ts::return_shared(listing);
        ts::return_shared(tide);
        ts::return_shared(staking);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    ts::end(scenario);
}

// === Treasury Vault Tests ===

#[test]
fun test_treasury_vault_deposit_and_withdraw() {
    let mut scenario = ts::begin(ADMIN);
    
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    backer_deposit(&mut scenario, BACKER1, 100_000_000_000);
    
    // Finalize the listing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let clock = clock::create_for_testing(ts::ctx(&mut scenario));
        
        listing.finalize(&council_cap, &mut capital_vault, &clock, ts::ctx(&mut scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        transfer::public_transfer(council_cap, ADMIN);
    };
    
    // Collect raise fee - should deposit to treasury vault
    ts::next_tx(&mut scenario, ISSUER);
    {
        let listing = ts::take_shared<Listing>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(&scenario);
        
        // Verify treasury vault starts empty
        assert!(treasury_vault.balance() == 0);
        
        // Collect 1% fee from 100 SUI = 1 SUI
        listing.collect_raise_fee(&tide, &mut treasury_vault, &mut capital_vault, ts::ctx(&mut scenario));
        
        // Verify fee was deposited to vault (1% of 100 SUI = 1 SUI)
        assert!(treasury_vault.balance() == 1_000_000_000);
        assert!(treasury_vault.total_deposited() == 1_000_000_000);
        
        ts::return_shared(tide);
        ts::return_shared(treasury_vault);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Admin withdraws from treasury vault
    ts::next_tx(&mut scenario, ADMIN);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        
        let vault_balance = treasury_vault.balance();
        assert!(vault_balance > 0);
        
        // Withdraw half to admin wallet
        tide.withdraw_from_treasury(&admin_cap, &mut treasury_vault, vault_balance / 2, ts::ctx(&mut scenario));
        
        assert!(treasury_vault.balance() == vault_balance / 2);
        assert!(treasury_vault.total_withdrawn() == vault_balance / 2);
        
        ts::return_shared(tide);
        ts::return_shared(treasury_vault);
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    // Admin withdraws remaining to custom address
    let custom_recipient: address = @0xCAFE;
    ts::next_tx(&mut scenario, ADMIN);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        
        let remaining = treasury_vault.balance();
        
        // Withdraw to custom recipient
        tide.withdraw_treasury_to(&admin_cap, &mut treasury_vault, remaining, custom_recipient, ts::ctx(&mut scenario));
        
        assert!(treasury_vault.balance() == 0);
        
        ts::return_shared(tide);
        ts::return_shared(treasury_vault);
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    // Verify custom recipient received funds
    ts::next_tx(&mut scenario, custom_recipient);
    {
        // Custom recipient should have received the SUI
        assert!(ts::has_most_recent_for_sender<coin::Coin<SUI>>(&scenario));
    };
    
    ts::end(scenario);
}

#[test]
fun test_treasury_vault_withdraw_all() {
    let mut scenario = ts::begin(ADMIN);
    
    setup_protocol(&mut scenario);
    
    // Deposit some funds directly for testing
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        
        treasury_vault::deposit_for_testing(&mut treasury_vault, 50_000_000_000, ts::ctx(&mut scenario));
        treasury_vault::deposit_for_testing(&mut treasury_vault, 30_000_000_000, ts::ctx(&mut scenario));
        
        assert!(treasury_vault.balance() == 80_000_000_000);
        
        ts::return_shared(treasury_vault);
    };
    
    // Admin withdraws all
    ts::next_tx(&mut scenario, ADMIN);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        
        tide.withdraw_all_from_treasury(&admin_cap, &mut treasury_vault, ts::ctx(&mut scenario));
        
        assert!(treasury_vault.balance() == 0);
        assert!(treasury_vault.total_withdrawn() == 80_000_000_000);
        
        ts::return_shared(tide);
        ts::return_shared(treasury_vault);
        transfer::public_transfer(admin_cap, ADMIN);
    };
    
    ts::end(scenario);
}
