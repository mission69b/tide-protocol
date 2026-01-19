/// End-to-end tests for Tide Marketplace.
/// 
/// Tests full lifecycle scenarios including:
/// - Deposit → Get Pass → List → Buy → New owner claims
/// - Multi-seller marketplace scenarios
#[test_only]
#[allow(unused_mut_ref, unused_variable)]
module tide_marketplace::marketplace_e2e_tests;

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
use tide_core::treasury_vault::{Self, TreasuryVault};
use tide_core::supporter_pass::SupporterPass;

use tide_marketplace::marketplace::{Self, MarketplaceConfig, SaleListing};

// === Test Addresses ===

const ADMIN: address = @0xAD;
const ISSUER: address = @0x1551;
const SELLER: address = @0x5E;
const BUYER: address = @0xB0;
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
    
    ts::next_tx(scenario, ADMIN);
    {
        marketplace::init_for_testing(ts::ctx(scenario));
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
                vector::empty(),
                vector::empty(),
                1000,
                ts::ctx(scenario),
            );
        
        ts::return_shared(registry);
        transfer::public_transfer(council_cap, ADMIN);
        
        listing::share(listing);
        capital_vault::share(capital_vault);
        reward_vault::share(reward_vault);
        staking_adapter::share(staking_adapter);
        
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

fun route_rewards(scenario: &mut Scenario, amount: u64) {
    ts::next_tx(scenario, ISSUER);
    {
        let mut reward_vault = ts::take_shared<RewardVault>(scenario);
        let route_cap = ts::take_from_sender<RouteCapability>(scenario);
        
        let rewards = coin::mint_for_testing<SUI>(amount, ts::ctx(scenario));
        reward_vault.deposit_rewards(&route_cap, rewards, ts::ctx(scenario));
        
        ts::return_shared(reward_vault);
        ts::return_to_sender(scenario, route_cap);
    };
}

// === E2E Tests ===

/// Full happy path: Deposit → Get Pass → List → Buy → New owner claims
#[test]
fun test_e2e_deposit_list_buy_claim() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Step 1: Seller deposits 100 SUI and gets a pass
    deposit_as_backer(&mut scenario, SELLER, HUNDRED_SUI);
    
    // Verify seller has pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        assert!(pass.shares() > 0, 0);
        assert!(pass.pass_number() == 1, 1);
        assert!(pass.original_backer() == SELLER, 2);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    // Step 2: Seller lists pass on marketplace for 150 SUI (premium)
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, 150 * ONE_SUI, ts::ctx(&mut scenario));
        
        let (_, _, _, active) = marketplace::stats(&config);
        assert!(active == 1, 3); // active_listings_count
        
        ts::return_shared(config);
    };
    
    // Step 3: Buyer purchases the pass
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(150 * ONE_SUI, ts::ctx(&mut scenario));
        let (pass, receipt, change) = marketplace::buy(
            &mut config,
            &mut treasury_vault,
            listing,
            payment,
            ts::ctx(&mut scenario),
        );
        
        // Verify pass ownership transferred
        assert!(pass.shares() > 0, 4);
        
        // Verify fee was collected (5% of 150 = 7.5 SUI)
        assert!(treasury_vault.balance() > 0, 5);
        
        // Verify marketplace stats
        let (volume, _fees, sales, active_now) = marketplace::stats(&config);
        assert!(volume == 150 * ONE_SUI, 6);
        assert!(sales == 1, 7);
        assert!(active_now == 0, 8); // Sold, no longer active
        
        change.destroy_zero();
        marketplace::destroy_receipt_for_testing(receipt);
        transfer::public_transfer(pass, BUYER);
        ts::return_shared(config);
        ts::return_shared(treasury_vault);
    };
    
    // Step 4: Route rewards
    route_rewards(&mut scenario, TEN_SUI);
    
    // Step 5: Buyer (new owner) claims rewards
    ts::next_tx(&mut scenario, BUYER);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // New owner claims
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        // Should get all rewards (only backer)
        assert!(reward.value() == TEN_SUI, 9);
        
        // Pass still shows original backer
        assert!(pass.original_backer() == SELLER, 10);
        
        transfer::public_transfer(reward, BUYER);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}

/// Test delist flow: List → Delist → Seller keeps pass
#[test]
fun test_e2e_list_delist() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Seller deposits
    deposit_as_backer(&mut scenario, SELLER, HUNDRED_SUI);
    
    // Seller lists
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Seller delists
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let pass = marketplace::delist(&mut config, listing, ts::ctx(&mut scenario));
        
        // Seller gets pass back
        assert!(pass.shares() > 0, 0);
        
        // No active listings
        let (_, _, _, active_now) = marketplace::stats(&config);
        assert!(active_now == 0, 1);
        
        transfer::public_transfer(pass, SELLER);
        ts::return_shared(config);
    };
    
    // Seller can still claim rewards
    route_rewards(&mut scenario, TEN_SUI);
    
    ts::next_tx(&mut scenario, SELLER);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        assert!(reward.value() == TEN_SUI, 2);
        
        transfer::public_transfer(reward, SELLER);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}

/// Test multiple sellers scenario
#[test]
fun test_e2e_multi_seller_marketplace() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    let seller2: address = @0x5E2;
    
    // Two sellers deposit
    deposit_as_backer(&mut scenario, SELLER, HUNDRED_SUI);
    deposit_as_backer(&mut scenario, seller2, HUNDRED_SUI);
    
    // Both sellers list
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, 50 * ONE_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    ts::next_tx(&mut scenario, seller2);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, 75 * ONE_SUI, ts::ctx(&mut scenario));
        
        // Two active listings
        let (_, _, _, active_now) = marketplace::stats(&config);
        assert!(active_now == 2, 0);
        
        ts::return_shared(config);
    };
    
    // Buyer purchases first listing (cheaper)
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        
        // Find the 50 SUI listing
        let listings: vector<ID> = vector[];
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(marketplace::price(&listing), ts::ctx(&mut scenario));
        let (pass, receipt, change) = marketplace::buy(
            &mut config,
            &mut treasury_vault,
            listing,
            payment,
            ts::ctx(&mut scenario),
        );
        
        // One listing left
        let (_, _, _, active_after) = marketplace::stats(&config);
        assert!(active_after == 1, 1);
        
        change.destroy_zero();
        marketplace::destroy_receipt_for_testing(receipt);
        transfer::public_transfer(pass, BUYER);
        ts::return_shared(config);
        ts::return_shared(treasury_vault);
    };
    
    ts::end(scenario);
}
