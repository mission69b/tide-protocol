/// End-to-end tests for Faith Router adapter.
/// 
/// Tests complete revenue routing flows:
/// - FAITH protocol revenue → faith_router → RewardVault → Backer claims
/// - Revenue routing → Loan auto-repayment via keeper harvest
/// - Multiple backers claiming proportionally
#[test_only]
#[allow(unused_mut_ref)]
module faith_router::router_e2e_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::coin;
use sui::sui::SUI;
use sui::clock;

use tide_core::tide::{Self, Tide};
use tide_core::council::{Self, CouncilCap};
use tide_core::registry::{Self, ListingRegistry};
use tide_core::listing::{Self, Listing};
use tide_core::capital_vault::{Self, CapitalVault};
use tide_core::reward_vault::{Self, RewardVault, RouteCapability};
use tide_core::staking_adapter;
use tide_core::treasury_vault;
use tide_core::supporter_pass::SupporterPass;

use faith_router::faith_router::{Self, FaithRouter};

// === Test Addresses ===

const ADMIN: address = @0xAD;
const ISSUER: address = @0x1551;
const FAITH_ADMIN: address = @0xFA17;
const BACKER1: address = @0xB1;
const BACKER2: address = @0xB2;
const VALIDATOR: address = @0xA1;

// === Test Constants ===

const ONE_SUI: u64 = 1_000_000_000;
const TEN_SUI: u64 = 10_000_000_000;
const HUNDRED_SUI: u64 = 100_000_000_000;

// === Helper Functions ===

fun setup_protocol(scenario: &mut Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        tide::init_for_testing(ts::ctx(scenario));
    };
    
    ts::next_tx(scenario, ADMIN);
    {
        council::init_for_testing(ts::ctx(scenario));
    };
    
    ts::next_tx(scenario, ADMIN);
    {
        registry::init_for_testing(ts::ctx(scenario));
    };
    
    ts::next_tx(scenario, ADMIN);
    {
        let vault = treasury_vault::new_for_testing(ts::ctx(scenario));
        treasury_vault::share(vault);
    };
}

fun create_listing_with_faith_router(scenario: &mut Scenario) {
    // Create listing
    ts::next_tx(scenario, ADMIN);
    {
        let mut registry = ts::take_shared<ListingRegistry>(scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(scenario);
        
        let (listing, capital_vault, reward_vault, staking_adapter, listing_cap, route_cap) = 
            listing::new(
                &mut registry,
                &council_cap,
                ADMIN,      // issuer = protocol operator
                ISSUER,     // release_recipient = artist
                VALIDATOR,
                vector::empty(),
                vector::empty(),
                1000, // 10% revenue routing to backers
                ts::ctx(scenario),
            );
        
        ts::return_shared(registry);
        transfer::public_transfer(council_cap, ADMIN);
        
        listing::share(listing);
        capital_vault::share(capital_vault);
        reward_vault::share(reward_vault);
        staking_adapter::share(staking_adapter);
        
        listing::transfer_cap(listing_cap, ADMIN);
        
        // Transfer route_cap to FAITH_ADMIN for router creation
        reward_vault::transfer_route_cap(route_cap, FAITH_ADMIN);
    };
    
    // Create faith_router with the route_cap
    ts::next_tx(scenario, FAITH_ADMIN);
    {
        let route_cap = ts::take_from_sender<RouteCapability>(scenario);
        
        let (router, router_cap) = faith_router::new(
            route_cap,
            1000, // 10% of FAITH revenue goes to Tide backers
            ts::ctx(scenario),
        );
        
        faith_router::share(router);
        transfer::public_transfer(router_cap, FAITH_ADMIN);
    };
}

fun activate_listing(scenario: &mut Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        let mut listing = ts::take_shared<Listing>(scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(scenario);
        let clock = clock::create_for_testing(ts::ctx(scenario));
        
        listing::activate(&mut listing, &council_cap, &clock, ts::ctx(scenario));
        
        clock::destroy_for_testing(clock);
        ts::return_shared(listing);
        transfer::public_transfer(council_cap, ADMIN);
    };
}

fun deposit_as_backer(scenario: &mut Scenario, backer: address, amount: u64) {
    ts::next_tx(scenario, backer);
    {
        let tide = ts::take_shared<Tide>(scenario);
        let mut listing = ts::take_shared<Listing>(scenario);
        let mut capital_vault = ts::take_shared<CapitalVault>(scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(scenario);
        let clock = clock::create_for_testing(ts::ctx(scenario));
        
        let deposit = coin::mint_for_testing<SUI>(amount, ts::ctx(scenario));
        
        let pass = listing::deposit(
            &mut listing,
            &tide,
            &mut capital_vault,
            &mut reward_vault,
            deposit,
            &clock,
            ts::ctx(scenario),
        );
        
        transfer::public_transfer(pass, backer);
        clock::destroy_for_testing(clock);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
        ts::return_shared(reward_vault);
    };
}

// === E2E Tests ===

/// Full flow: FAITH revenue → faith_router → RewardVault → Backer claims
#[test]
fun test_e2e_faith_revenue_to_backer_claim() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing_with_faith_router(&mut scenario);
    activate_listing(&mut scenario);
    
    // Step 1: Backer deposits 100 SUI
    deposit_as_backer(&mut scenario, BACKER1, HUNDRED_SUI);
    
    // Verify backer has pass
    ts::next_tx(&mut scenario, BACKER1);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        assert!(pass.shares() > 0, 0);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    // Step 2: FAITH protocol generates revenue (100 SUI total)
    // First calculate how much goes to backers, then route that portion
    ts::next_tx(&mut scenario, FAITH_ADMIN);
    {
        let mut router = ts::take_shared<FaithRouter>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        
        // Simulate FAITH protocol revenue (100 SUI total)
        let total_revenue = 100 * ONE_SUI;
        let mut revenue_coin = coin::mint_for_testing<SUI>(total_revenue, ts::ctx(&mut scenario));
        
        // Calculate backer portion (10% = 10 SUI)
        let backer_amount = faith_router::calculate_revenue(&router, total_revenue);
        assert!(backer_amount == 10 * ONE_SUI, 1);
        
        // Split and route the backer portion
        let backer_portion = revenue_coin.split(backer_amount, ts::ctx(&mut scenario));
        faith_router::route(
            &mut router,
            &mut reward_vault,
            backer_portion,
            ts::ctx(&mut scenario),
        );
        
        // Verify router stats
        assert!(faith_router::total_routed(&router) == 10 * ONE_SUI, 2);
        
        // Issuer keeps remaining 90 SUI
        assert!(revenue_coin.value() == 90 * ONE_SUI, 3);
        transfer::public_transfer(revenue_coin, FAITH_ADMIN);
        
        ts::return_shared(router);
        ts::return_shared(reward_vault);
    };
    
    // Step 3: Backer claims rewards
    ts::next_tx(&mut scenario, BACKER1);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        // Backer should get all 10 SUI (only backer)
        assert!(reward.value() == TEN_SUI, 3);
        
        // Pass tracks claimed amount
        assert!(pass.total_claimed() == TEN_SUI, 4u64);
        
        transfer::public_transfer(reward, BACKER1);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}

/// Multi-backer proportional distribution
#[test]
fun test_e2e_multi_backer_proportional_claims() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing_with_faith_router(&mut scenario);
    activate_listing(&mut scenario);
    
    // Step 1: Two backers deposit (BACKER1: 75 SUI, BACKER2: 25 SUI)
    // This gives them 75% and 25% shares respectively
    deposit_as_backer(&mut scenario, BACKER1, 75 * ONE_SUI);
    deposit_as_backer(&mut scenario, BACKER2, 25 * ONE_SUI);
    
    // Step 2: Route 100 SUI revenue through faith_router
    ts::next_tx(&mut scenario, FAITH_ADMIN);
    {
        let mut router = ts::take_shared<FaithRouter>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        
        let total_revenue = 100 * ONE_SUI;
        let mut revenue_coin = coin::mint_for_testing<SUI>(total_revenue, ts::ctx(&mut scenario));
        
        // 10% = 10 SUI goes to RewardVault
        let backer_amount = faith_router::calculate_revenue(&router, total_revenue);
        let backer_portion = revenue_coin.split(backer_amount, ts::ctx(&mut scenario));
        faith_router::route(&mut router, &mut reward_vault, backer_portion, ts::ctx(&mut scenario));
        
        transfer::public_transfer(revenue_coin, FAITH_ADMIN);
        ts::return_shared(router);
        ts::return_shared(reward_vault);
    };
    
    // Step 3: BACKER1 claims (should get ~75% of 10 SUI = 7.5 SUI)
    ts::next_tx(&mut scenario, BACKER1);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        // BACKER1 gets 75% of rewards
        // Due to fixed-point precision, we check approximately
        assert!(reward.value() >= 7 * ONE_SUI, 0);
        assert!(reward.value() <= 8 * ONE_SUI, 1);
        
        transfer::public_transfer(reward, BACKER1);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    // Step 4: BACKER2 claims (should get ~25% of 10 SUI = 2.5 SUI)
    ts::next_tx(&mut scenario, BACKER2);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        // BACKER2 gets 25% of rewards
        assert!(reward.value() >= 2 * ONE_SUI, 2);
        assert!(reward.value() <= 3 * ONE_SUI, 3);
        
        transfer::public_transfer(reward, BACKER2);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}

/// Multiple revenue routing cycles
#[test]
fun test_e2e_multiple_revenue_cycles() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing_with_faith_router(&mut scenario);
    activate_listing(&mut scenario);
    
    // Backer deposits
    deposit_as_backer(&mut scenario, BACKER1, HUNDRED_SUI);
    
    // Cycle 1: Route 50 SUI revenue
    ts::next_tx(&mut scenario, FAITH_ADMIN);
    {
        let mut router = ts::take_shared<FaithRouter>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        
        let total_revenue = 50 * ONE_SUI;
        let mut revenue_coin = coin::mint_for_testing<SUI>(total_revenue, ts::ctx(&mut scenario));
        let backer_amount = faith_router::calculate_revenue(&router, total_revenue);
        let backer_portion = revenue_coin.split(backer_amount, ts::ctx(&mut scenario));
        faith_router::route(&mut router, &mut reward_vault, backer_portion, ts::ctx(&mut scenario));
        
        assert!(faith_router::total_routed(&router) == 5 * ONE_SUI, 0);
        
        transfer::public_transfer(revenue_coin, FAITH_ADMIN);
        ts::return_shared(router);
        ts::return_shared(reward_vault);
    };
    
    // Backer claims from cycle 1
    ts::next_tx(&mut scenario, BACKER1);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() == 5 * ONE_SUI, 1);
        
        transfer::public_transfer(reward, BACKER1);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    // Cycle 2: Route another 100 SUI revenue
    ts::next_tx(&mut scenario, FAITH_ADMIN);
    {
        let mut router = ts::take_shared<FaithRouter>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        
        let total_revenue = 100 * ONE_SUI;
        let mut revenue_coin = coin::mint_for_testing<SUI>(total_revenue, ts::ctx(&mut scenario));
        let backer_amount = faith_router::calculate_revenue(&router, total_revenue);
        let backer_portion = revenue_coin.split(backer_amount, ts::ctx(&mut scenario));
        faith_router::route(&mut router, &mut reward_vault, backer_portion, ts::ctx(&mut scenario));
        
        // Total routed should be 5 + 10 = 15 SUI
        assert!(faith_router::total_routed(&router) == 15 * ONE_SUI, 2);
        
        transfer::public_transfer(revenue_coin, FAITH_ADMIN);
        ts::return_shared(router);
        ts::return_shared(reward_vault);
    };
    
    // Backer claims from cycle 2
    ts::next_tx(&mut scenario, BACKER1);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() == 10 * ONE_SUI, 3);
        
        // Total claimed across both cycles
        assert!(pass.total_claimed() == 15 * ONE_SUI, 4);
        
        transfer::public_transfer(reward, BACKER1);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}

/// Test revenue_bps getter
#[test]
fun test_e2e_router_revenue_bps() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing_with_faith_router(&mut scenario);
    
    ts::next_tx(&mut scenario, FAITH_ADMIN);
    {
        let router = ts::take_shared<FaithRouter>(&scenario);
        
        // Verify configured bps
        assert!(faith_router::revenue_bps(&router) == 1000, 0); // 10%
        
        ts::return_shared(router);
    };
    
    ts::end(scenario);
}

/// Test zero bps configuration (issuer keeps everything)
#[test]
fun test_e2e_zero_bps_issuer_keeps_all() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    
    // Create listing without faith_router initially
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut registry = ts::take_shared<ListingRegistry>(&scenario);
        let council_cap = ts::take_from_sender<CouncilCap>(&scenario);
        
        let (listing, capital_vault, reward_vault, staking_adapter, listing_cap, route_cap) = 
            listing::new(
                &mut registry,
                &council_cap,
                ADMIN,      // issuer = protocol operator
                ISSUER,     // release_recipient = artist
                VALIDATOR,
                vector::empty(),
                vector::empty(),
                1000,
                ts::ctx(&mut scenario),
            );
        
        ts::return_shared(registry);
        transfer::public_transfer(council_cap, ADMIN);
        
        listing::share(listing);
        capital_vault::share(capital_vault);
        reward_vault::share(reward_vault);
        staking_adapter::share(staking_adapter);
        listing::transfer_cap(listing_cap, ADMIN);
        
        // Create router with 0% bps
        let (router, router_cap) = faith_router::new(
            route_cap,
            0, // 0% to backers
            ts::ctx(&mut scenario),
        );
        
        faith_router::share(router);
        transfer::public_transfer(router_cap, FAITH_ADMIN);
    };
    
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, BACKER1, HUNDRED_SUI);
    
    // Route revenue (0% goes to backers)
    ts::next_tx(&mut scenario, FAITH_ADMIN);
    {
        let router = ts::take_shared<FaithRouter>(&scenario);
        
        let total_revenue = 100 * ONE_SUI;
        let revenue_coin = coin::mint_for_testing<SUI>(total_revenue, ts::ctx(&mut scenario));
        
        // 0% = 0 SUI to backers
        let backer_amount = faith_router::calculate_revenue(&router, total_revenue);
        assert!(backer_amount == 0, 0);
        
        // Nothing routed to backers
        assert!(faith_router::total_routed(&router) == 0, 1);
        
        // Issuer keeps all
        transfer::public_transfer(revenue_coin, FAITH_ADMIN);
        ts::return_shared(router);
    };
    
    ts::end(scenario);
}
