/// Tests for Tide Marketplace.
#[test_only]
module tide_marketplace::marketplace_tests;

use sui::test_scenario::{Self as ts};
use sui::coin::{Self};
use sui::sui::SUI;

use tide_core::supporter_pass::{Self, SupporterPass};
use tide_core::treasury_vault::{Self, TreasuryVault};

use tide_marketplace::marketplace::{Self, MarketplaceConfig, SaleListing};

// === Test Addresses ===

const ADMIN: address = @0xAD;
const SELLER: address = @0x5E;
const BUYER: address = @0xB0;

// === Test Constants ===

const ONE_SUI: u64 = 1_000_000_000;
const TEN_SUI: u64 = 10_000_000_000;

// === Helper Functions ===

fun setup_marketplace(scenario: &mut ts::Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        marketplace::init_for_testing(ts::ctx(scenario));
    };
}

fun create_pass_for_seller(scenario: &mut ts::Scenario, shares: u128) {
    ts::next_tx(scenario, ADMIN);
    {
        let listing_id = object::id_from_address(@0x123);
        let pass = supporter_pass::mint_for_testing_with_number(
            listing_id,
            1, // pass_number
            SELLER, // original_backer
            shares,
            0, // current_index
            ts::ctx(scenario),
        );
        transfer::public_transfer(pass, SELLER);
    };
}

fun create_treasury_vault(scenario: &mut ts::Scenario) {
    ts::next_tx(scenario, ADMIN);
    {
        let vault = treasury_vault::new_for_testing(ts::ctx(scenario));
        treasury_vault::share(vault);
    };
}

// === Basic Tests ===

#[test]
fun test_init() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    
    ts::next_tx(&mut scenario, ADMIN);
    {
        let config = ts::take_shared<MarketplaceConfig>(&scenario);
        
        assert!(marketplace::admin(&config) == ADMIN, 0);
        assert!(!marketplace::is_paused(&config), 1);
        
        let (volume, fees, sales, active) = marketplace::stats(&config);
        assert!(volume == 0, 2);
        assert!(fees == 0, 3);
        assert!(sales == 0, 4);
        assert!(active == 0, 5);
        
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
fun test_list_for_sale() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    // Seller lists pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        let _listing_id = marketplace::list_for_sale(
            &mut config,
            pass,
            TEN_SUI,
            ts::ctx(&mut scenario),
        );
        
        // Verify stats updated
        let (_, _, _, active) = marketplace::stats(&config);
        assert!(active == 1, 0);
        
        ts::return_shared(config);
    };
    
    // Verify listing exists
    ts::next_tx(&mut scenario, SELLER);
    {
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        assert!(marketplace::price(&listing) == TEN_SUI, 1);
        assert!(marketplace::seller(&listing) == SELLER, 2);
        assert!(marketplace::shares(&listing) == 100, 3);
        
        ts::return_shared(listing);
    };
    
    ts::end(scenario);
}

#[test]
fun test_delist() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    // Seller lists pass
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
        
        // Verify stats updated
        let (_, _, _, active) = marketplace::stats(&config);
        assert!(active == 0, 0);
        
        // Verify pass returned
        assert!(pass.shares() == 100, 1);
        
        transfer::public_transfer(pass, SELLER);
        ts::return_shared(config);
    };
    
    // Verify seller has pass back
    ts::next_tx(&mut scenario, SELLER);
    {
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        assert!(pass.shares() == 100, 2);
        ts::return_to_sender(&scenario, pass);
    };
    
    ts::end(scenario);
}

#[test]
fun test_buy() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    create_treasury_vault(&mut scenario);
    
    // Seller lists pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Buyer purchases
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(TEN_SUI, ts::ctx(&mut scenario));
        
        let (pass, receipt, change) = marketplace::buy(
            &mut config,
            &mut treasury_vault,
            listing,
            payment,
            ts::ctx(&mut scenario),
        );
        
        // Verify stats
        let (volume, fees, sales, active) = marketplace::stats(&config);
        assert!(volume == TEN_SUI, 0);
        assert!(fees == 500_000_000, 1); // 5% of 10 SUI
        assert!(sales == 1, 2);
        assert!(active == 0, 3);
        
        // Verify treasury received fee
        assert!(treasury_vault.balance() == 500_000_000, 4);
        
        // Verify pass
        assert!(pass.shares() == 100, 5);
        
        // Verify no change (exact payment)
        assert!(change.value() == 0, 6);
        
        transfer::public_transfer(pass, BUYER);
        marketplace::destroy_receipt_for_testing(receipt);
        change.destroy_zero();
        ts::return_shared(config);
        ts::return_shared(treasury_vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_buy_with_change() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    create_treasury_vault(&mut scenario);
    
    // Seller lists pass at 10 SUI
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Buyer pays 15 SUI, should get 5 SUI change
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(15 * ONE_SUI, ts::ctx(&mut scenario));
        
        let (pass, receipt, change) = marketplace::buy(
            &mut config,
            &mut treasury_vault,
            listing,
            payment,
            ts::ctx(&mut scenario),
        );
        
        // Verify change is 5 SUI
        assert!(change.value() == 5 * ONE_SUI, 0);
        
        transfer::public_transfer(pass, BUYER);
        transfer::public_transfer(change, BUYER);
        marketplace::destroy_receipt_for_testing(receipt);
        ts::return_shared(config);
        ts::return_shared(treasury_vault);
    };
    
    ts::end(scenario);
}

#[test]
fun test_fee_calculation() {
    // 5% of 10 SUI = 0.5 SUI
    assert!(marketplace::calculate_fee(TEN_SUI) == 500_000_000, 0);
    
    // 5% of 1 SUI = 0.05 SUI
    assert!(marketplace::calculate_fee(ONE_SUI) == 50_000_000, 1);
    
    // 5% of 100 SUI = 5 SUI
    assert!(marketplace::calculate_fee(100 * ONE_SUI) == 5 * ONE_SUI, 2);
}

#[test]
fun test_update_price() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    // Seller lists pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Seller updates price
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut listing = ts::take_shared<SaleListing>(&scenario);
        
        assert!(marketplace::price(&listing) == TEN_SUI, 0);
        
        marketplace::update_price(&mut listing, 20 * ONE_SUI, ts::ctx(&mut scenario));
        
        assert!(marketplace::price(&listing) == 20 * ONE_SUI, 1);
        
        ts::return_shared(listing);
    };
    
    ts::end(scenario);
}

#[test]
fun test_pause_unpause() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    
    // Admin pauses
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        
        assert!(!marketplace::is_paused(&config), 0);
        
        marketplace::pause(&mut config, ts::ctx(&mut scenario));
        
        assert!(marketplace::is_paused(&config), 1);
        
        ts::return_shared(config);
    };
    
    // Admin unpauses
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        
        marketplace::unpause(&mut config, ts::ctx(&mut scenario));
        
        assert!(!marketplace::is_paused(&config), 2);
        
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
fun test_transfer_admin() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    
    let new_admin: address = @0xAAA;
    
    // Admin transfers
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        
        assert!(marketplace::admin(&config) == ADMIN, 0);
        
        marketplace::transfer_admin(&mut config, new_admin, ts::ctx(&mut scenario));
        
        assert!(marketplace::admin(&config) == new_admin, 1);
        
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
fun test_delist_when_paused() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    // Seller lists pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Admin pauses
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        marketplace::pause(&mut config, ts::ctx(&mut scenario));
        ts::return_shared(config);
    };
    
    // Seller can still delist when paused
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let pass = marketplace::delist(&mut config, listing, ts::ctx(&mut scenario));
        
        transfer::public_transfer(pass, SELLER);
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

// === Error Tests ===

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::EZeroPrice)]
fun test_list_zero_price_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, 0, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::EPriceTooLow)]
fun test_list_below_minimum_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        // Try to list below minimum (0.1 SUI)
        marketplace::list_for_sale(&mut config, pass, 50_000_000, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::ENotSeller)]
fun test_delist_wrong_seller_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    // Seller lists pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Buyer tries to delist (should fail)
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let pass = marketplace::delist(&mut config, listing, ts::ctx(&mut scenario));
        
        transfer::public_transfer(pass, BUYER);
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::EInsufficientPayment)]
fun test_buy_insufficient_payment_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    create_treasury_vault(&mut scenario);
    
    // Seller lists pass at 10 SUI
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Buyer tries to pay only 5 SUI
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(5 * ONE_SUI, ts::ctx(&mut scenario));
        
        let (pass, receipt, change) = marketplace::buy(
            &mut config,
            &mut treasury_vault,
            listing,
            payment,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(pass, BUYER);
        transfer::public_transfer(change, BUYER);
        marketplace::destroy_receipt_for_testing(receipt);
        ts::return_shared(config);
        ts::return_shared(treasury_vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::EMarketplacePaused)]
fun test_list_when_paused_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    // Admin pauses
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        marketplace::pause(&mut config, ts::ctx(&mut scenario));
        ts::return_shared(config);
    };
    
    // Seller tries to list (should fail)
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::EMarketplacePaused)]
fun test_buy_when_paused_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    create_treasury_vault(&mut scenario);
    
    // Seller lists pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Admin pauses
    ts::next_tx(&mut scenario, ADMIN);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        marketplace::pause(&mut config, ts::ctx(&mut scenario));
        ts::return_shared(config);
    };
    
    // Buyer tries to buy (should fail)
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let mut treasury_vault = ts::take_shared<TreasuryVault>(&scenario);
        let listing = ts::take_shared<SaleListing>(&scenario);
        
        let payment = coin::mint_for_testing<SUI>(TEN_SUI, ts::ctx(&mut scenario));
        
        let (pass, receipt, change) = marketplace::buy(
            &mut config,
            &mut treasury_vault,
            listing,
            payment,
            ts::ctx(&mut scenario),
        );
        
        transfer::public_transfer(pass, BUYER);
        transfer::public_transfer(change, BUYER);
        marketplace::destroy_receipt_for_testing(receipt);
        ts::return_shared(config);
        ts::return_shared(treasury_vault);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::ENotSeller)]
fun test_update_price_wrong_seller_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    create_pass_for_seller(&mut scenario, 100);
    
    // Seller lists pass
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        let pass = ts::take_from_sender<SupporterPass>(&scenario);
        
        marketplace::list_for_sale(&mut config, pass, TEN_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(config);
    };
    
    // Buyer tries to update price (should fail)
    ts::next_tx(&mut scenario, BUYER);
    {
        let mut listing = ts::take_shared<SaleListing>(&scenario);
        
        marketplace::update_price(&mut listing, 20 * ONE_SUI, ts::ctx(&mut scenario));
        
        ts::return_shared(listing);
    };
    
    ts::end(scenario);
}

// === Admin Access Control Tests ===

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::ENotAdmin)]
fun test_pause_wrong_caller_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    
    // Non-admin tries to pause (should fail)
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        marketplace::pause(&mut config, ts::ctx(&mut scenario));
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

#[test]
#[expected_failure(abort_code = tide_marketplace::marketplace::ENotAdmin)]
fun test_transfer_admin_wrong_caller_fails() {
    let mut scenario = ts::begin(ADMIN);
    setup_marketplace(&mut scenario);
    
    // Non-admin tries to transfer admin (should fail)
    ts::next_tx(&mut scenario, SELLER);
    {
        let mut config = ts::take_shared<MarketplaceConfig>(&scenario);
        marketplace::transfer_admin(&mut config, SELLER, ts::ctx(&mut scenario));
        ts::return_shared(config);
    };
    
    ts::end(scenario);
}

// === View Function Tests ===

#[test]
fun test_view_functions() {
    assert!(marketplace::fee_bps() == 500, 0);
    assert!(marketplace::min_price() == 100_000_000, 1);
}
