/// Tests for Self-Paying Loans.
#[test_only]
module tide_loans::loan_vault_tests;

use sui::test_scenario::{Self as ts, Scenario};
use sui::coin;
use sui::sui::SUI;
use sui::clock;

use tide_core::tide::{Self, Tide, AdminCap};
use tide_core::council::{Self, CouncilCap};
use tide_core::registry::{Self, ListingRegistry};
use tide_core::listing::{Self, Listing};
use tide_core::capital_vault::{Self, CapitalVault};
use tide_core::reward_vault::{Self, RewardVault};
use tide_core::staking_adapter;
use tide_core::treasury_vault;
use tide_core::supporter_pass::SupporterPass;

use tide_loans::loan_vault::{Self, LoanVault, LoanReceipt};

// === Test Addresses ===

const ADMIN: address = @0xAD;
const ISSUER: address = @0x1551;
const BACKER: address = @0xBA;

// === Test Constants ===

const ONE_SUI: u64 = 1_000_000_000;
const HUNDRED_SUI: u64 = 100_000_000_000;
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
    
    // Initialize loan vault
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
        
        // Transfer caps to admin (protocol operator)
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

fun deposit_as_backer(scenario: &mut Scenario, amount: u64) {
    ts::next_tx(scenario, BACKER);
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
        
        transfer::public_transfer(pass, BACKER);
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

// === Basic Tests ===

#[test]
fun test_init() {
    let mut scenario = ts::begin(ADMIN);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        loan_vault::init_for_testing(ts::ctx(&mut scenario));
    };
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let vault = ts::take_shared<LoanVault>(&scenario);
        
        assert!(loan_vault::liquidity(&vault) == 0, 0);
        assert!(loan_vault::total_borrowed(&vault) == 0, 1);
        assert!(loan_vault::active_loans(&vault) == 0, 2);
        assert!(!loan_vault::is_paused(&vault), 3);
        
        ts::return_shared(vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_deposit_liquidity() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        let liquidity = coin::mint_for_testing<SUI>(HUNDRED_SUI, ts::ctx(&mut scenario));
        loan_vault::deposit_liquidity(&mut vault, &admin_cap, liquidity, ts::ctx(&mut scenario));
        
        assert!(loan_vault::liquidity(&vault) == HUNDRED_SUI, 0);
        
        ts::return_shared(vault);
        ts::return_to_sender(&scenario, admin_cap);
    };
    
    ts::end(scenario);
}

#[test]
fun test_withdraw_liquidity() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        let withdrawn = loan_vault::withdraw_liquidity(&mut vault, &admin_cap, 50 * ONE_SUI, ts::ctx(&mut scenario));
        
        assert!(withdrawn.value() == 50 * ONE_SUI, 0);
        assert!(loan_vault::liquidity(&vault) == 50 * ONE_SUI, 1);
        
        transfer::public_transfer(withdrawn, ADMIN);
        ts::return_shared(vault);
        ts::return_to_sender(&scenario, admin_cap);
    };
    
    ts::end(scenario);
}

#[test]
fun test_borrow() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Backer borrows against their pass
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Borrow 40% LTV = 40 SUI (max with new conservative LTV)
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            40 * ONE_SUI,
            ts::ctx(&mut scenario),
        );
        
        // After 1% origination fee, should receive ~39.6 SUI (40 - 1%)
        assert!(loan_coin.value() == 39_600_000_000, 0);
        
        // Vault state updated
        assert!(loan_vault::active_loans(&vault) == 1, 1);
        assert!(loan_vault::total_borrowed(&vault) == 40 * ONE_SUI, 2);
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_manual_repay_full() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Backer borrows
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
            40 * ONE_SUI,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Backer repays fully
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(50 * ONE_SUI, ts::ctx(&mut scenario));
        let refund = loan_vault::repay(&mut vault, &receipt, payment, ts::ctx(&mut scenario));
        
        // Should have refund (paid 50, owed ~40)
        assert!(refund.value() > 9 * ONE_SUI, 0);
        
        // Active loans should be 0 now
        assert!(loan_vault::active_loans(&vault) == 0, 1);
        
        transfer::public_transfer(refund, BACKER);
        ts::return_shared(vault);
        ts::return_to_sender(&scenario, receipt);
    };
    
    ts::end(scenario);
}

#[test]
fun test_withdraw_collateral_after_repay() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Backer borrows
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
            40 * ONE_SUI,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Backer repays fully
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(50 * ONE_SUI, ts::ctx(&mut scenario));
        let refund = loan_vault::repay(&mut vault, &receipt, payment, ts::ctx(&mut scenario));
        
        transfer::public_transfer(refund, BACKER);
        ts::return_shared(vault);
        ts::return_to_sender(&scenario, receipt);
    };
    
    // Backer withdraws collateral
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let pass = loan_vault::withdraw_collateral(&mut vault, receipt, ts::ctx(&mut scenario));
        
        // Got pass back!
        assert!(pass.shares() > 0, 0);
        
        transfer::public_transfer(pass, BACKER);
        ts::return_shared(vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_pause_unpause() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        assert!(!loan_vault::is_paused(&vault), 0);
        
        loan_vault::pause(&mut vault, &admin_cap, ts::ctx(&mut scenario));
        assert!(loan_vault::is_paused(&vault), 1);
        
        loan_vault::unpause(&mut vault, &admin_cap, ts::ctx(&mut scenario));
        assert!(!loan_vault::is_paused(&vault), 2);
        
        ts::return_shared(vault);
        ts::return_to_sender(&scenario, admin_cap);
    };
    
    ts::end(scenario);
}

#[test]
fun test_config_updates() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        // Update max LTV to 60%
        loan_vault::update_max_ltv(&mut vault, &admin_cap, 6000);
        
        let config = loan_vault::config(&vault);
        assert!(loan_vault::max_ltv_bps(&config) == 6000, 0);
        
        // Update interest rate to 10%
        loan_vault::update_interest_rate(&mut vault, &admin_cap, 1000);
        
        let config = loan_vault::config(&vault);
        assert!(loan_vault::interest_rate_bps(&config) == 1000, 1);
        
        ts::return_shared(vault);
        ts::return_to_sender(&scenario, admin_cap);
    };
    
    ts::end(scenario);
}

// === Error Tests ===

#[test]
#[expected_failure(abort_code = tide_loans::loan_vault::ELoanVaultPaused)]
fun test_borrow_when_paused_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Admin pauses vault
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let admin_cap = ts::take_from_sender<AdminCap>(&scenario);
        
        loan_vault::pause(&mut vault, &admin_cap, ts::ctx(&mut scenario));
        
        ts::return_shared(vault);
        ts::return_to_sender(&scenario, admin_cap);
    };
    
    // Backer tries to borrow (should fail due to pause)
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
            40 * ONE_SUI, // Within LTV, should fail on pause check
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_loans::loan_vault::EExceedsMaxLTV)]
fun test_borrow_exceeds_ltv_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Backer tries to borrow more than 40% LTV (max is 40%)
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let tide = ts::take_shared<Tide>(&scenario);
        let listing = ts::take_shared<Listing>(&scenario);
        let capital_vault = ts::take_shared<CapitalVault>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Try to borrow 60 SUI on 100 SUI collateral (60% LTV, exceeds 40% max)
        let (receipt, loan_coin) = loan_vault::borrow(
            &mut vault,
            &listing,
            &tide,
            &capital_vault,
            pass,
            60 * ONE_SUI,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_loans::loan_vault::EInsufficientLiquidity)]
fun test_borrow_insufficient_liquidity_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    
    // Note: No liquidity added to vault
    
    // Backer tries to borrow (should fail on insufficient liquidity)
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
            40 * ONE_SUI, // Within LTV, should fail on liquidity check
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_loans::loan_vault::ELoanNotRepaid)]
fun test_withdraw_before_repaid_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Backer borrows
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
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    // Backer tries to withdraw without repaying (should fail)
    ts::next_tx(&mut scenario, BACKER);
    {
        let mut vault = ts::take_shared<LoanVault>(&scenario);
        let receipt = ts::take_from_sender<LoanReceipt>(&scenario);
        
        let pass = loan_vault::withdraw_collateral(&mut vault, receipt, ts::ctx(&mut scenario));
        
        transfer::public_transfer(pass, BACKER);
        ts::return_shared(vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_loans::loan_vault::EBelowMinLoan)]
fun test_borrow_below_minimum_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_protocol(&mut scenario);
    create_listing(&mut scenario);
    activate_listing(&mut scenario);
    deposit_as_backer(&mut scenario, HUNDRED_SUI);
    add_liquidity_to_vault(&mut scenario, HUNDRED_SUI);
    
    // Backer tries to borrow less than 1 SUI
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
            500_000_000, // 0.5 SUI, below 1 SUI minimum
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(receipt, BACKER);
        transfer::public_transfer(loan_coin, BACKER);
        ts::return_shared(vault);
        ts::return_shared(tide);
        ts::return_shared(listing);
        ts::return_shared(capital_vault);
    };
    
    ts::end(scenario);
}

// === View Function Tests ===

#[test]
fun test_default_config() {
    let mut scenario = ts::begin(ADMIN);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        loan_vault::init_for_testing(ts::ctx(&mut scenario));
    };
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let vault = ts::take_shared<LoanVault>(&scenario);
        
        let config = loan_vault::config(&vault);
        
        // Default values (conservative for v1)
        assert!(loan_vault::max_ltv_bps(&config) == 4000, 0); // 40%
        assert!(loan_vault::interest_rate_bps(&config) == 500, 1); // 5%
        
        ts::return_shared(vault);
    };
    
    ts::end(scenario);
}
