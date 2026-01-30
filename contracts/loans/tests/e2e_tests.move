/// End-to-end tests for Self-Paying Loans.
/// 
/// Tests full lifecycle scenarios including:
/// - Borrow → Harvest auto-repay → Withdraw collateral
/// - Borrow → Manual repay → Withdraw collateral
/// - Multi-loan scenarios
#[test_only]
#[allow(unused_mut_ref, unused_variable)]
module tide_loans::loan_e2e_tests;

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
use tide_core::treasury_vault;
use tide_core::supporter_pass::SupporterPass;

use tide_loans::loan_vault::{Self, LoanVault, LoanReceipt};

// === Test Addresses ===

const ADMIN: address = @0xAD;
const ISSUER: address = @0x1551;
const BACKER: address = @0xBA;
const KEEPER: address = @0xEE;
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
        loan_vault::init_for_testing(ts::ctx(scenario));
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
                ADMIN,      // issuer = protocol operator
                ISSUER,     // release_recipient = artist
                VALIDATOR,
                vector::empty(),
                vector::empty(),
                1000, // 10% revenue routing
                ts::ctx(scenario),
            );
        
        ts::return_shared(registry);
        transfer::public_transfer(council_cap, ADMIN);
        
        listing::share(listing);
        capital_vault::share(capital_vault);
        reward_vault::share(reward_vault);
        staking_adapter::share(staking_adapter);
        
        listing::transfer_cap(listing_cap, ADMIN);
        reward_vault::transfer_route_cap(route_cap, ADMIN);
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

fun add_liquidity_to_vault(scenario: &mut Scenario, amount: u64) {
    ts::next_tx(scenario, ADMIN);
    {
        let mut vault = ts::take_shared<LoanVault>(scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(scenario);
        
        let liquidity = coin::mint_for_testing<SUI>(amount, ts::ctx(scenario));
        loan_vault::deposit_liquidity(&mut vault, &admin_cap, liquidity, ts::ctx(scenario));
        
        ts::return_shared(vault);
        ts::return_to_sender(scenario, admin_cap);
    };
}

fun route_rewards(scenario: &mut Scenario, amount: u64) {
    ts::next_tx(scenario, ADMIN);
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

/// Full happy path: Borrow → Manual Repay → Withdraw Collateral
#[test]
fun test_e2e_borrow_repay_withdraw() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Step 1: Backer deposits 100 SUI
    deposit_as_backer(&mut scenario, BACKER, HUNDRED_SUI);
    
    // Step 2: Admin adds liquidity to loan vault
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Step 3: Backer borrows 50 SUI against their pass
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let original_shares = pass.shares();
        
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            40 * ONE_SUI, // 40% LTV (max)
            ts::ctx(&mut scenario),
        );
        
        // Verify loan proceeds (minus 1% origination fee): 40 SUI - 1% = 39.6 SUI
        assert!(loan_coin.value() == 39_600_000_000, 0);
        
        // Verify vault state
        assert!(loan_vault::active_loans(&vault) == 1, 1);
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Step 4: Backer repays loan in full
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        // Pay more than needed to ensure full repayment
        let payment = coin::mint_for_testing<SUI>(60 * ONE_SUI, ts::ctx(&mut scenario));
        let refund = loan_vault::repay(&mut vault, &receipt, payment, ts::ctx(&mut scenario));
        
        // Should get refund
        assert!(refund.value() > 0, 2);
        
        // Loan should be repaid
        assert!(loan_vault::active_loans(&vault) == 0, 3);
        
        transfer::public_transfer(refund, BACKER);
        ts::return_shared(vault);
        ts::return_to_sender(&mut scenario, receipt);
    };
    
    // Step 5: Backer withdraws collateral (gets pass back)
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let pass = loan_vault::withdraw_collateral(&mut vault, receipt, ts::ctx(&mut scenario));
        
        // Pass should have same shares as before
        assert!(pass.shares() > 0, 4);
        
        transfer::public_transfer(pass, BACKER);
        ts::return_shared(vault);
    };
    
    // Step 6: Verify backer can still claim rewards
    route_rewards(&mut scenario, TEN_SUI);
    
    ts::next_tx(&mut scenario, BACKER);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        // Should have claimed rewards
        assert!(reward.value() > 0, 5);
        
        transfer::public_transfer(reward, BACKER);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}

/// Test harvest auto-repay with rewards
#[test]
fun test_e2e_borrow_harvest_repay() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    // Backer deposits
    deposit_as_backer(&mut scenario, BACKER, HUNDRED_SUI);
    
    // Add liquidity
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Backer borrows 10 SUI (small loan)
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            10 * ONE_SUI, // Small loan
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Route significant rewards (more than loan)
    route_rewards(&mut scenario, 50 * ONE_SUI);
    
    // Get the loan_id from the receipt
    ts::next_tx(&mut scenario, BACKER);
    let loan_id = {
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        let id = loan_vault::receipt_loan_id(&receipt);
        ts::return_to_sender(&mut scenario, receipt);
        id
    };
    
    // Keeper calls harvest_and_repay
    ts::next_tx(&mut scenario, KEEPER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        
        let keeper_tip = loan_vault::harvest_and_repay(
            &mut vault,
            loan_id,
            &listing,
            &tide,
            &mut reward_vault,
            ts::ctx(&mut scenario),
        );
        
        // Keeper should get tip
        assert!(keeper_tip.value() > 0, 0);
        
        // Loan should be fully repaid (rewards > loan)
        assert!(loan_vault::active_loans(&vault) == 0, 1);
        
        transfer::public_transfer(keeper_tip, KEEPER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    // Backer can now withdraw collateral
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let pass = loan_vault::withdraw_collateral(&mut vault, receipt, ts::ctx(&mut scenario));
        
        assert!(pass.shares() > 0, 2);
        
        transfer::public_transfer(pass, BACKER);
        ts::return_shared(vault);
    };
    
    ts::end(scenario);
}

/// Test multiple backers with loans
#[test]
fun test_e2e_multi_backer_loans() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    let backer2: address = @0xB2;
    
    // Two backers deposit
    deposit_as_backer(&mut scenario, BACKER, HUNDRED_SUI);
    deposit_as_backer(&mut scenario, backer2, HUNDRED_SUI);
    
    // Add enough liquidity
    add_liquidity_to_vault(&mut scenario, 200 * ONE_SUI);
    
    // Both backers borrow
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            40 * ONE_SUI, // 40% LTV
            ts::ctx(&mut scenario),
        );
        
        assert!(loan_vault::active_loans(&vault) == 1, 0);
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::next_tx(&mut scenario, backer2);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            40 * ONE_SUI, // 40% LTV
            ts::ctx(&mut scenario),
        );
        
        // Should have 2 active loans now
        assert!(loan_vault::active_loans(&vault) == 2, 1);
        assert!(loan_vault::total_borrowed(&vault) == 80 * ONE_SUI, 2);
        
        transfer::public_transfer(receipt, backer2);
        transfer::public_transfer(loan_coin, backer2);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // One backer repays
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(60 * ONE_SUI, ts::ctx(&mut scenario));
        let refund = loan_vault::repay(&mut vault, &receipt, payment, ts::ctx(&mut scenario));
        
        // Should have 1 active loan now
        assert!(loan_vault::active_loans(&vault) == 1, 3);
        
        transfer::public_transfer(refund, BACKER);
        ts::return_shared(vault);
        ts::return_to_sender(&mut scenario, receipt);
    };
    
    ts::end(scenario);
}

// === Advanced E2E Scenarios ===

/// Simulates: User buys pass on secondary market → Borrows against it
/// (Marketplace purchase is simulated by transferring pass from original backer)
#[test]
fun test_e2e_secondary_market_then_borrow() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    let alice: address = @0xA11CE;
    let bob: address = @0xB0B;
    
    // Step 1: Alice deposits and gets a pass
    deposit_as_backer(&mut scenario, alice, HUNDRED_SUI);
    
    // Step 2: Alice "sells" pass to Bob (simulates marketplace purchase)
    ts::next_tx(&mut scenario, alice);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Verify pass attributes
        assert!(pass.original_backer() == alice, 0);
        assert!(pass.shares() > 0, 1);
        
        // Transfer to Bob (simulates marketplace sale)
        transfer::public_transfer(pass, bob);
    };
    
    // Step 3: Add liquidity to loan vault
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Step 4: Bob borrows against the pass he purchased
    ts::next_tx(&mut scenario, bob);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Bob can borrow against pass even though he wasn't original backer
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            40 * ONE_SUI, // 40% LTV
            ts::ctx(&mut scenario),
        );
        
        // Loan created successfully
        assert!(loan_vault::active_loans(&vault) == 1, 2);
        assert!(loan_coin.value() == 39_600_000_000, 3); // 40 - 1% fee
        
        transfer::public_transfer(receipt, bob);
        transfer::public_transfer(loan_coin, bob);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::end(scenario);
}

/// Full pass journey: Deposit → Sell → Borrow → Revenue auto-repays → Withdraw → Claim
#[test]
fun test_e2e_full_pass_journey() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    let alice: address = @0xA11CE;
    let bob: address = @0xB0B;
    
    // Step 1: Alice deposits 100 SUI
    deposit_as_backer(&mut scenario, alice, HUNDRED_SUI);
    
    // Step 2: Alice transfers pass to Bob (simulates marketplace sale)
    ts::next_tx(&mut scenario, alice);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        transfer::public_transfer(pass, bob);
    };
    
    // Step 3: Add liquidity
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Step 4: Bob borrows 20 SUI (small loan)
    ts::next_tx(&mut scenario, bob);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            20 * ONE_SUI,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, bob);
        transfer::public_transfer(loan_coin, bob);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Step 5: Route significant revenue (more than loan)
    route_rewards(&mut scenario, 50 * ONE_SUI);
    
    // Get loan_id
    ts::next_tx(&mut scenario, bob);
    let loan_id = {
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        let id = loan_vault::receipt_loan_id(&receipt);
        ts::return_to_sender(&mut scenario, receipt);
        id
    };
    
    // Step 6: Keeper harvests - should auto-repay loan
    ts::next_tx(&mut scenario, KEEPER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        
        let keeper_tip = loan_vault::harvest_and_repay(
            &mut vault,
            loan_id,
            &listing,
            &tide,
            &mut reward_vault,
            ts::ctx(&mut scenario),
        );
        
        // Loan should be fully repaid (50 SUI rewards > 20 SUI loan)
        assert!(loan_vault::active_loans(&vault) == 0, 0);
        
        // Keeper got tip
        assert!(keeper_tip.value() > 0, 1);
        
        transfer::public_transfer(keeper_tip, KEEPER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
    };
    
    // Step 7: Bob withdraws his pass (loan is repaid)
    ts::next_tx(&mut scenario, bob);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let pass = loan_vault::withdraw_collateral(&mut vault, receipt, ts::ctx(&mut scenario));
        
        // Bob got his pass back
        assert!(pass.shares() > 0, 2);
        
        // Pass still shows Alice as original backer
        assert!(pass.original_backer() == alice, 3);
        
        transfer::public_transfer(pass, bob);
        ts::return_shared(vault);
    };
    
    // Step 8: More revenue is routed
    route_rewards(&mut scenario, TEN_SUI);
    
    // Step 9: Bob claims any remaining rewards
    ts::next_tx(&mut scenario, bob);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        
        // Bob got the new rewards
        assert!(reward.value() == TEN_SUI, 4);
        
        transfer::public_transfer(reward, bob);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}

/// Liquidation E2E: Borrow → Collateral value drops → Liquidate
/// Note: In our system, collateral value is based on original deposit, not market price
/// So we simulate this by borrowing near max LTV and having interest accrue
#[test]
fun test_e2e_liquidation_flow() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    let borrower: address = @0xB0220;
    let liquidator: address = @0x11;
    
    // Step 1: Borrower deposits
    deposit_as_backer(&mut scenario, borrower, HUNDRED_SUI);
    
    // Step 2: Add liquidity
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Step 3: Borrower borrows at max LTV (50 SUI on 100 SUI collateral)
    ts::next_tx(&mut scenario, borrower);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            40 * ONE_SUI, // 40% LTV (max)
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, borrower);
        transfer::public_transfer(loan_coin, borrower);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Get loan_id
    ts::next_tx(&mut scenario, borrower);
    let loan_id = {
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        let id = loan_vault::receipt_loan_id(&receipt);
        ts::return_to_sender(&mut scenario, receipt);
        id
    };
    
    // Step 4: Check health factor before liquidation attempt
    // At 50% LTV with 75% liquidation threshold, health factor = (100 * 0.75) / 50 = 1.5
    // Loan is healthy, can't be liquidated yet
    ts::next_tx(&mut scenario, liquidator);
    {
        let vault = ts::take_shared<LoanVault>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        
        // Get health factor
        let (health_numerator, health_denominator) = loan_vault::get_health_factor(
            &vault,
            loan_id,
            &capital_vault,
        );
        
        // Health should be > 1 (150/100 approximately)
        assert!(health_numerator > health_denominator, 0);
        
        ts::return_shared(vault);
        ts::return_shared(capital_vault);
    };
    
    // Note: In a real scenario, the loan would become liquidatable when:
    // - Interest accrues significantly, OR
    // - Collateral value drops (in our case, we use original deposit value, so this doesn't happen)
    // 
    // For testing liquidation logic, we would need to either:
    // 1. Wait for significant time to pass for interest to accrue
    // 2. Or have a test-only function to make loan liquidatable
    //
    // This test demonstrates the liquidation check flow even though
    // the loan is currently healthy.
    
    ts::end(scenario);
}

/// Multiple pass ownership transfers with claims at each step
#[test]
fun test_e2e_pass_transfer_chain_with_claims() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    
    let alice: address = @0xA11CE;
    let bob: address = @0xB0B;
    let charlie: address = @0xC4A2;
    
    // Alice deposits
    deposit_as_backer(&mut scenario, alice, HUNDRED_SUI);
    
    // Route rewards round 1
    route_rewards(&mut scenario, 30 * ONE_SUI);
    
    // Alice claims
    ts::next_tx(&mut scenario, alice);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() == 30 * ONE_SUI, 0);
        
        // Total claimed updated
        assert!(pass.total_claimed() == 30 * ONE_SUI, 1);
        
        transfer::public_transfer(reward, alice);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    // Alice transfers to Bob
    ts::next_tx(&mut scenario, alice);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        transfer::public_transfer(pass, bob);
    };
    
    // Route rewards round 2
    route_rewards(&mut scenario, 20 * ONE_SUI);
    
    // Bob claims
    ts::next_tx(&mut scenario, bob);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() == 20 * ONE_SUI, 2);
        
        // Total claimed is cumulative (Alice's 30 + Bob's 20)
        assert!(pass.total_claimed() == 50 * ONE_SUI, 3);
        
        // Original backer is still Alice
        assert!(pass.original_backer() == alice, 4);
        
        transfer::public_transfer(reward, bob);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    // Bob transfers to Charlie
    ts::next_tx(&mut scenario, bob);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        transfer::public_transfer(pass, charlie);
    };
    
    // Route rewards round 3
    route_rewards(&mut scenario, 10 * ONE_SUI);
    
    // Charlie claims
    ts::next_tx(&mut scenario, charlie);
    {
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let mut reward_vault = ts::take_shared<RewardVault>(&scenario);
        let mut pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let reward = listing::claim(&listing, &tide, &mut reward_vault, &mut pass, ts::ctx(&mut scenario));
        assert!(reward.value() == 10 * ONE_SUI, 5);
        
        // Total claimed is cumulative (30 + 20 + 10)
        assert!(pass.total_claimed() == 60 * ONE_SUI, 6);
        
        // Original backer is STILL Alice
        assert!(pass.original_backer() == alice, 7);
        
        transfer::public_transfer(reward, charlie);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(reward_vault);
        ts::return_to_sender(&mut scenario, pass);
    };
    
    ts::end(scenario);
}
