/// Self-Paying Loans - DeFi expansion for Tide Protocol.
/// 
/// Allows SupporterPass holders to borrow against their yield-bearing NFTs.
/// Rewards automatically repay the loan via keeper-called harvests.
/// 
/// Key Features:
/// - Borrow up to 50% LTV against SupporterPass
/// - Self-paying: rewards auto-repay the loan
/// - Conservative parameters protect treasury
/// - Insurance fund for black swan events
/// 
/// Fee Structure:
/// - Origination fee: 1% (on borrow)
/// - Interest rate: 5% APR (simple interest)
/// - Liquidation fee: 5% (on liquidation)
/// - Keeper tip: 0.1% (on harvest)
module tide_loans::loan_vault;

use sui::sui::SUI;
use sui::coin::{Self, Coin};
use sui::balance::{Self, Balance};
use sui::dynamic_field as df;
use sui::dynamic_object_field as dof;
use sui::event;

use tide_core::supporter_pass::SupporterPass;
use tide_core::listing::Listing;
use tide_core::tide::{Tide, AdminCap};
use tide_core::reward_vault::RewardVault;

// === Error Codes ===

const ELoanVaultPaused: u64 = 1;
const EExceedsMaxLTV: u64 = 2;
const EInsufficientLiquidity: u64 = 3;
const ELoanNotActive: u64 = 4;
const ELoanNotRepaid: u64 = 5;
const ENotBorrower: u64 = 6;
const ELoanHealthy: u64 = 7;
const EInsufficientPayment: u64 = 8;
const EBelowMinLoan: u64 = 9;
const EZeroAmount: u64 = 10;

// === Constants ===

/// Contract version for upgrade compatibility.
const VERSION: u64 = 1;

/// Loan status values
const LOAN_ACTIVE: u8 = 0;
const LOAN_REPAID: u8 = 1;
const LOAN_LIQUIDATED: u8 = 2;

/// Basis points denominator
const BPS_DENOMINATOR: u64 = 10_000;

/// Milliseconds in a year (for interest calculation)
const MS_PER_YEAR: u64 = 365 * 24 * 60 * 60 * 1000;

// === Default Parameters ===

const DEFAULT_MAX_LTV_BPS: u64 = 5000;              // 50%
const DEFAULT_LIQUIDATION_THRESHOLD_BPS: u64 = 7500; // 75%
const DEFAULT_INTEREST_RATE_BPS: u64 = 500;         // 5% APR
const DEFAULT_ORIGINATION_FEE_BPS: u64 = 100;       // 1%
const DEFAULT_LIQUIDATION_FEE_BPS: u64 = 500;       // 5%
const DEFAULT_KEEPER_TIP_BPS: u64 = 10;             // 0.1%
const DEFAULT_INSURANCE_FUND_BPS: u64 = 2000;       // 20%
const DEFAULT_MIN_LOAN: u64 = 1_000_000_000;        // 1 SUI

// === Structs ===

/// Global loan vault configuration (shared, singleton).
public struct LoanVault has key {
    id: UID,
    /// Contract version for upgrade compatibility.
    version: u64,
    /// Available liquidity for lending.
    liquidity: Balance<SUI>,
    /// Insurance fund for covering losses.
    insurance_fund: Balance<SUI>,
    /// Total borrowed (outstanding).
    total_borrowed: u64,
    /// Total repaid (lifetime).
    total_repaid: u64,
    /// Total fees earned (lifetime).
    total_fees_earned: u64,
    /// Active loan count.
    active_loans: u64,
    /// Total loans created (lifetime).
    total_loans_created: u64,
    /// Configuration parameters.
    config: LoanConfig,
    /// Admin address.
    admin: address,
    /// Pause flag.
    paused: bool,
}

/// Loan configuration parameters.
public struct LoanConfig has copy, drop, store {
    /// Maximum LTV in basis points (5000 = 50%).
    max_ltv_bps: u64,
    /// Liquidation threshold in basis points (7500 = 75%).
    liquidation_threshold_bps: u64,
    /// Interest rate in basis points (500 = 5% APR).
    interest_rate_bps: u64,
    /// Origination fee in basis points (100 = 1%).
    origination_fee_bps: u64,
    /// Liquidation fee in basis points (500 = 5%).
    liquidation_fee_bps: u64,
    /// Keeper tip in basis points (10 = 0.1%).
    keeper_tip_bps: u64,
    /// Insurance fund allocation in basis points (2000 = 20%).
    insurance_fund_bps: u64,
    /// Minimum loan amount in MIST.
    min_loan: u64,
}

/// Individual loan record (stored as dynamic field).
public struct Loan has store {
    /// Borrower address.
    borrower: address,
    /// Collateral pass ID.
    pass_id: ID,
    /// Listing this pass belongs to.
    listing_id: ID,
    /// Original loan principal.
    principal: u64,
    /// Accrued interest.
    interest_accrued: u64,
    /// Amount repaid so far.
    amount_repaid: u64,
    /// Collateral value at time of borrow.
    collateral_value: u64,
    /// Epoch when loan created.
    created_epoch: u64,
    /// Last update timestamp (ms).
    last_update_ms: u64,
    /// Loan status.
    status: u8,
}

/// Loan receipt NFT (owned by borrower, proves loan ownership).
public struct LoanReceipt has key, store {
    id: UID,
    /// ID of the loan in LoanVault.
    loan_id: ID,
    /// Borrower address.
    borrower: address,
    /// Collateral pass ID.
    pass_id: ID,
    /// Original principal.
    principal: u64,
}

/// Dynamic field key for loans.
public struct LoanKey has copy, drop, store { loan_id: ID }

/// Dynamic field key for collateral passes.
public struct PassKey has copy, drop, store { pass_id: ID }

// === Events ===

public struct LoanCreated has copy, drop {
    loan_id: ID,
    borrower: address,
    pass_id: ID,
    listing_id: ID,
    principal: u64,
    collateral_value: u64,
    ltv_bps: u64,
    origination_fee: u64,
    epoch: u64,
}

public struct LoanRepayment has copy, drop {
    loan_id: ID,
    amount: u64,
    source: u8,  // 0=harvest, 1=manual
    remaining_balance: u64,
    epoch: u64,
}

public struct LoanFullyRepaid has copy, drop {
    loan_id: ID,
    borrower: address,
    total_principal: u64,
    total_interest: u64,
    excess_returned: u64,
    epoch: u64,
}

public struct LoanLiquidated has copy, drop {
    loan_id: ID,
    borrower: address,
    liquidator: address,
    amount_paid: u64,
    collateral_value: u64,
    liquidation_fee: u64,
    epoch: u64,
}

public struct CollateralWithdrawn has copy, drop {
    loan_id: ID,
    borrower: address,
    pass_id: ID,
    epoch: u64,
}

public struct HarvestExecuted has copy, drop {
    loan_id: ID,
    rewards_claimed: u64,
    applied_to_loan: u64,
    keeper_tip: u64,
    keeper: address,
    remaining_balance: u64,
    epoch: u64,
}

public struct LiquidityDeposited has copy, drop {
    amount: u64,
    depositor: address,
    new_balance: u64,
    epoch: u64,
}

public struct LiquidityWithdrawn has copy, drop {
    amount: u64,
    recipient: address,
    new_balance: u64,
    epoch: u64,
}

public struct VaultPaused has copy, drop {
    paused: bool,
    admin: address,
    epoch: u64,
}

// === Initialization ===

fun init(ctx: &mut TxContext) {
    let vault = LoanVault {
        id: object::new(ctx),
        version: VERSION,
        liquidity: balance::zero(),
        insurance_fund: balance::zero(),
        total_borrowed: 0,
        total_repaid: 0,
        total_fees_earned: 0,
        active_loans: 0,
        total_loans_created: 0,
        config: LoanConfig {
            max_ltv_bps: DEFAULT_MAX_LTV_BPS,
            liquidation_threshold_bps: DEFAULT_LIQUIDATION_THRESHOLD_BPS,
            interest_rate_bps: DEFAULT_INTEREST_RATE_BPS,
            origination_fee_bps: DEFAULT_ORIGINATION_FEE_BPS,
            liquidation_fee_bps: DEFAULT_LIQUIDATION_FEE_BPS,
            keeper_tip_bps: DEFAULT_KEEPER_TIP_BPS,
            insurance_fund_bps: DEFAULT_INSURANCE_FUND_BPS,
            min_loan: DEFAULT_MIN_LOAN,
        },
        admin: ctx.sender(),
        paused: false,
    };
    transfer::share_object(vault);
}

// === Core Functions ===

/// Borrow SUI against a SupporterPass.
/// 
/// The pass is locked as collateral until the loan is fully repaid.
/// A 1% origination fee is deducted from the loan amount.
/// 
/// Returns: (LoanReceipt, Coin<SUI> loan proceeds)
public fun borrow(
    vault: &mut LoanVault,
    listing: &Listing,
    _tide: &Tide,
    capital_vault: &tide_core::capital_vault::CapitalVault,
    pass: SupporterPass,
    loan_amount: u64,
    ctx: &mut TxContext,
): (LoanReceipt, Coin<SUI>) {
    // Validate vault state
    assert!(!vault.paused, ELoanVaultPaused);
    assert!(loan_amount >= vault.config.min_loan, EBelowMinLoan);
    assert!(vault.liquidity.value() >= loan_amount, EInsufficientLiquidity);
    
    // Validate pass belongs to listing
    pass.assert_listing(listing.id());
    
    let pass_id = pass.id();
    let listing_id = pass.listing_id();
    let borrower = ctx.sender();
    
    // Calculate collateral value (conservative: use share proportion of total principal)
    let collateral_value = calculate_collateral_value(&pass, capital_vault);
    
    // Validate collateral has value
    assert!(collateral_value > 0, EZeroAmount);
    
    // Validate LTV
    let max_loan = (collateral_value * vault.config.max_ltv_bps) / BPS_DENOMINATOR;
    assert!(loan_amount <= max_loan, EExceedsMaxLTV);
    
    // Calculate origination fee
    let origination_fee = (loan_amount * vault.config.origination_fee_bps) / BPS_DENOMINATOR;
    let net_loan = loan_amount - origination_fee;
    
    // Create loan record
    let loan_id = object::new(ctx);
    let loan_id_inner = loan_id.to_inner();
    
    let loan = Loan {
        borrower,
        pass_id,
        listing_id,
        principal: loan_amount,
        interest_accrued: 0,
        amount_repaid: 0,
        collateral_value,
        created_epoch: ctx.epoch(),
        last_update_ms: ctx.epoch_timestamp_ms(),
        status: LOAN_ACTIVE,
    };
    
    // Store loan and pass in vault
    df::add(&mut vault.id, LoanKey { loan_id: loan_id_inner }, loan);
    dof::add(&mut vault.id, PassKey { pass_id }, pass);
    
    // Update vault state
    vault.total_borrowed = vault.total_borrowed + loan_amount;
    vault.active_loans = vault.active_loans + 1;
    vault.total_loans_created = vault.total_loans_created + 1;
    vault.total_fees_earned = vault.total_fees_earned + origination_fee;
    
    // Allocate fee to insurance fund
    let insurance_amount = (origination_fee * vault.config.insurance_fund_bps) / BPS_DENOMINATOR;
    let _treasury_amount = origination_fee - insurance_amount;
    
    // Split liquidity for loan
    let loan_coin = coin::from_balance(vault.liquidity.split(net_loan), ctx);
    
    // Add insurance portion (from fee already in liquidity conceptually - we just don't give it out)
    // Actually, the fee was never in the vault, so we need to track it differently
    // For simplicity in v1, we don't physically move the fee - it's already "earned"
    // The insurance fund will be funded from repayments
    
    // Create receipt
    let receipt = LoanReceipt {
        id: loan_id,
        loan_id: loan_id_inner,
        borrower,
        pass_id,
        principal: loan_amount,
    };
    
    // Emit event
    event::emit(LoanCreated {
        loan_id: loan_id_inner,
        borrower,
        pass_id,
        listing_id,
        principal: loan_amount,
        collateral_value,
        ltv_bps: (loan_amount * BPS_DENOMINATOR) / collateral_value,
        origination_fee,
        epoch: ctx.epoch(),
    });
    
    (receipt, loan_coin)
}

/// Harvest rewards from collateralized pass and apply to loan.
/// 
/// Permissionless - anyone can call (keeper model).
/// Keeper receives a 0.1% tip from harvested rewards.
/// 
/// Returns: Keeper tip coin
public fun harvest_and_repay(
    vault: &mut LoanVault,
    loan_id: ID,
    listing: &Listing,
    tide: &Tide,
    reward_vault: &mut RewardVault,
    ctx: &mut TxContext,
): Coin<SUI> {
    // First get loan info we need (read-only)
    let (pass_id, borrower, loan_status) = {
        let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
        (loan.pass_id, loan.borrower, loan.status)
    };
    assert!(loan_status == LOAN_ACTIVE, ELoanNotActive);
    
    // Accrue interest on the loan
    {
        let loan = df::borrow_mut<LoanKey, Loan>(&mut vault.id, LoanKey { loan_id });
        accrue_interest(loan, vault.config.interest_rate_bps, ctx);
    };
    
    // Borrow pass from vault and claim rewards
    let pass = dof::borrow_mut<PassKey, SupporterPass>(&mut vault.id, PassKey { pass_id });
    
    // Calculate claimable rewards
    let claimable = reward_vault.calculate_claimable(
        pass.shares(),
        pass.claim_index(),
    );
    
    // If nothing to claim, return zero coin
    if (claimable == 0) {
        return coin::zero(ctx)
    };
    
    // Claim rewards using listing::claim
    let mut reward_coin = tide_core::listing::claim(listing, tide, reward_vault, pass, ctx);
    let reward_amount = reward_coin.value();
    
    // Calculate keeper tip
    let keeper_tip_amount = (reward_amount * vault.config.keeper_tip_bps) / BPS_DENOMINATOR;
    let net_rewards = reward_amount - keeper_tip_amount;
    
    // Now update the loan with repayment
    let (applied, excess, remaining_balance) = {
        let loan = df::borrow_mut<LoanKey, Loan>(&mut vault.id, LoanKey { loan_id });
        let outstanding = loan.principal + loan.interest_accrued - loan.amount_repaid;
        
        let (applied, excess) = if (net_rewards >= outstanding) {
            // Loan fully repaid!
            loan.amount_repaid = loan.principal + loan.interest_accrued;
            loan.status = LOAN_REPAID;
            vault.active_loans = vault.active_loans - 1;
            (outstanding, net_rewards - outstanding)
        } else {
            // Partial repayment
            loan.amount_repaid = loan.amount_repaid + net_rewards;
            (net_rewards, 0)
        };
        
        (applied, excess, loan.principal + loan.interest_accrued - loan.amount_repaid)
    };
    
    // Update vault totals
    vault.total_repaid = vault.total_repaid + applied;
    
    // Calculate insurance allocation from repayment
    let insurance_from_repay = (applied * vault.config.insurance_fund_bps) / BPS_DENOMINATOR;
    vault.insurance_fund.join(reward_coin.split(insurance_from_repay, ctx).into_balance());
    
    // Split out keeper tip
    let keeper_tip = reward_coin.split(keeper_tip_amount, ctx);
    
    // The rest goes to repaying the loan (back to liquidity)
    let repay_amount = applied - insurance_from_repay;
    if (repay_amount > 0 && reward_coin.value() >= repay_amount) {
        vault.liquidity.join(reward_coin.split(repay_amount, ctx).into_balance());
    };
    
    // Check if loan was fully repaid
    let loan_status_after = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id }).status;
    
    // Emit events
    event::emit(HarvestExecuted {
        loan_id,
        rewards_claimed: reward_amount,
        applied_to_loan: applied,
        keeper_tip: keeper_tip_amount,
        keeper: ctx.sender(),
        remaining_balance,
        epoch: ctx.epoch(),
    });
    
    if (loan_status_after == LOAN_REPAID) {
        let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
        event::emit(LoanFullyRepaid {
            loan_id,
            borrower: loan.borrower,
            total_principal: loan.principal,
            total_interest: loan.interest_accrued,
            excess_returned: excess,
            epoch: ctx.epoch(),
        });
        
        // Send excess to borrower
        if (excess > 0 && reward_coin.value() >= excess) {
            let excess_coin = reward_coin.split(excess, ctx);
            transfer::public_transfer(excess_coin, borrower);
        };
    };
    
    // Destroy any remaining dust
    if (reward_coin.value() > 0) {
        vault.liquidity.join(reward_coin.into_balance());
    } else {
        reward_coin.destroy_zero();
    };
    
    keeper_tip
}

/// Manually repay loan (partially or fully).
/// Anyone can repay, but only receipt holder can withdraw collateral.
public fun repay(
    vault: &mut LoanVault,
    receipt: &LoanReceipt,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
): Coin<SUI> {
    let loan_id = receipt.loan_id;
    
    // Get loan
    let loan = df::borrow_mut<LoanKey, Loan>(&mut vault.id, LoanKey { loan_id });
    assert!(loan.status == LOAN_ACTIVE, ELoanNotActive);
    
    // Accrue interest
    accrue_interest(loan, vault.config.interest_rate_bps, ctx);
    
    let payment_amount = payment.value();
    assert!(payment_amount > 0, EZeroAmount);
    
    // Calculate outstanding
    let outstanding = loan.principal + loan.interest_accrued - loan.amount_repaid;
    
    // Apply payment
    let (applied, refund_amount) = if (payment_amount >= outstanding) {
        // Full repayment
        loan.amount_repaid = loan.principal + loan.interest_accrued;
        loan.status = LOAN_REPAID;
        vault.active_loans = vault.active_loans - 1;
        (outstanding, payment_amount - outstanding)
    } else {
        // Partial repayment
        loan.amount_repaid = loan.amount_repaid + payment_amount;
        (payment_amount, 0)
    };
    
    // Update vault totals
    vault.total_repaid = vault.total_repaid + applied;
    
    // Add payment to liquidity
    vault.liquidity.join(payment.split(applied, ctx).into_balance());
    
    let remaining_balance = loan.principal + loan.interest_accrued - loan.amount_repaid;
    
    // Emit event
    event::emit(LoanRepayment {
        loan_id,
        amount: applied,
        source: 1, // manual
        remaining_balance,
        epoch: ctx.epoch(),
    });
    
    if (loan.status == LOAN_REPAID) {
        event::emit(LoanFullyRepaid {
            loan_id,
            borrower: loan.borrower,
            total_principal: loan.principal,
            total_interest: loan.interest_accrued,
            excess_returned: refund_amount,
            epoch: ctx.epoch(),
        });
    };
    
    // Return refund (remaining payment)
    payment
}

/// Withdraw collateral after loan is fully repaid.
/// Burns the LoanReceipt.
public fun withdraw_collateral(
    vault: &mut LoanVault,
    receipt: LoanReceipt,
    ctx: &mut TxContext,
): SupporterPass {
    let loan_id = receipt.loan_id;
    
    // Verify caller is borrower
    assert!(ctx.sender() == receipt.borrower, ENotBorrower);
    
    // Get loan
    let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
    assert!(loan.status == LOAN_REPAID, ELoanNotRepaid);
    
    let pass_id = loan.pass_id;
    let borrower = loan.borrower;
    
    // Remove pass from vault
    let pass = dof::remove<PassKey, SupporterPass>(&mut vault.id, PassKey { pass_id });
    
    // Emit event
    event::emit(CollateralWithdrawn {
        loan_id,
        borrower,
        pass_id,
        epoch: ctx.epoch(),
    });
    
    // Burn receipt
    let LoanReceipt { id, loan_id: _, borrower: _, pass_id: _, principal: _ } = receipt;
    id.delete();
    
    pass
}

/// Liquidate an unhealthy loan.
/// Anyone can call if health factor < 1.
/// Liquidator pays remaining loan and receives collateral.
#[allow(lint(self_transfer))]
public fun liquidate(
    vault: &mut LoanVault,
    loan_id: ID,
    capital_vault: &tide_core::capital_vault::CapitalVault,
    mut payment: Coin<SUI>,
    ctx: &mut TxContext,
): SupporterPass {
    // First get loan info (read-only)
    let (pass_id, borrower, loan_status) = {
        let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
        (loan.pass_id, loan.borrower, loan.status)
    };
    assert!(loan_status == LOAN_ACTIVE, ELoanNotActive);
    
    // Accrue interest
    {
        let loan = df::borrow_mut<LoanKey, Loan>(&mut vault.id, LoanKey { loan_id });
        accrue_interest(loan, vault.config.interest_rate_bps, ctx);
    };
    
    // Get pass for current collateral value
    let pass = dof::borrow<PassKey, SupporterPass>(&vault.id, PassKey { pass_id });
    let current_collateral = calculate_collateral_value(pass, capital_vault);
    
    // Get loan info after interest accrual
    let (outstanding, liquidation_fee) = {
        let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
        let outstanding = loan.principal + loan.interest_accrued - loan.amount_repaid;
        let liquidation_fee = (outstanding * vault.config.liquidation_fee_bps) / BPS_DENOMINATOR;
        (outstanding, liquidation_fee)
    };
    
    // Calculate health factor
    // health = (collateral × liquidation_threshold) / outstanding
    let threshold_value = (current_collateral * vault.config.liquidation_threshold_bps) / BPS_DENOMINATOR;
    
    // Check if liquidatable (health < 1 means threshold_value < outstanding)
    assert!(threshold_value < outstanding, ELoanHealthy);
    
    // Validate payment covers outstanding
    assert!(payment.value() >= outstanding, EInsufficientPayment);
    
    // Update loan status
    {
        let loan = df::borrow_mut<LoanKey, Loan>(&mut vault.id, LoanKey { loan_id });
        loan.amount_repaid = loan.principal + loan.interest_accrued;
        loan.status = LOAN_LIQUIDATED;
    };
    vault.active_loans = vault.active_loans - 1;
    
    // Update vault totals
    vault.total_repaid = vault.total_repaid + outstanding;
    vault.total_fees_earned = vault.total_fees_earned + liquidation_fee;
    
    // Take payment
    vault.liquidity.join(payment.split(outstanding, ctx).into_balance());
    
    // Add liquidation fee to insurance fund
    let insurance_from_fee = (liquidation_fee * vault.config.insurance_fund_bps) / BPS_DENOMINATOR;
    if (payment.value() >= insurance_from_fee) {
        vault.insurance_fund.join(payment.split(insurance_from_fee, ctx).into_balance());
    };
    
    // Remove pass and give to liquidator
    let pass = dof::remove<PassKey, SupporterPass>(&mut vault.id, PassKey { pass_id });
    
    // Emit event
    event::emit(LoanLiquidated {
        loan_id,
        borrower,
        liquidator: ctx.sender(),
        amount_paid: outstanding,
        collateral_value: current_collateral,
        liquidation_fee,
        epoch: ctx.epoch(),
    });
    
    // Return any excess payment
    if (payment.value() > 0) {
        transfer::public_transfer(payment, ctx.sender());
    } else {
        payment.destroy_zero();
    };
    
    pass
}

// === Admin Functions ===

/// Deposit liquidity to the vault (admin only).
public fun deposit_liquidity(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    liquidity: Coin<SUI>,
    ctx: &TxContext,
) {
    let amount = liquidity.value();
    vault.liquidity.join(liquidity.into_balance());
    
    event::emit(LiquidityDeposited {
        amount,
        depositor: ctx.sender(),
        new_balance: vault.liquidity.value(),
        epoch: ctx.epoch(),
    });
}

/// Withdraw liquidity from the vault (admin only).
public fun withdraw_liquidity(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(vault.liquidity.value() >= amount, EInsufficientLiquidity);
    
    let coin = coin::from_balance(vault.liquidity.split(amount), ctx);
    
    event::emit(LiquidityWithdrawn {
        amount,
        recipient: ctx.sender(),
        new_balance: vault.liquidity.value(),
        epoch: ctx.epoch(),
    });
    
    coin
}

/// Withdraw from insurance fund (admin only, emergency).
public fun withdraw_insurance(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    amount: u64,
    ctx: &mut TxContext,
): Coin<SUI> {
    assert!(vault.insurance_fund.value() >= amount, EInsufficientLiquidity);
    coin::from_balance(vault.insurance_fund.split(amount), ctx)
}

/// Pause the vault (admin only).
public fun pause(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    vault.paused = true;
    
    event::emit(VaultPaused {
        paused: true,
        admin: ctx.sender(),
        epoch: ctx.epoch(),
    });
}

/// Unpause the vault (admin only).
public fun unpause(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    ctx: &TxContext,
) {
    vault.paused = false;
    
    event::emit(VaultPaused {
        paused: false,
        admin: ctx.sender(),
        epoch: ctx.epoch(),
    });
}

/// Update max LTV (admin only).
public fun update_max_ltv(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    new_ltv_bps: u64,
) {
    assert!(new_ltv_bps <= BPS_DENOMINATOR, EZeroAmount);
    vault.config.max_ltv_bps = new_ltv_bps;
}

/// Update interest rate (admin only).
public fun update_interest_rate(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    new_rate_bps: u64,
) {
    vault.config.interest_rate_bps = new_rate_bps;
}

/// Update liquidation threshold (admin only).
public fun update_liquidation_threshold(
    vault: &mut LoanVault,
    _admin_cap: &AdminCap,
    new_threshold_bps: u64,
) {
    assert!(new_threshold_bps <= BPS_DENOMINATOR, EZeroAmount);
    vault.config.liquidation_threshold_bps = new_threshold_bps;
}

// === View Functions ===

/// Get vault liquidity.
public fun liquidity(vault: &LoanVault): u64 {
    vault.liquidity.value()
}

/// Get insurance fund balance.
public fun insurance_fund_balance(vault: &LoanVault): u64 {
    vault.insurance_fund.value()
}

/// Get total borrowed (outstanding).
public fun total_borrowed(vault: &LoanVault): u64 {
    vault.total_borrowed
}

/// Get total repaid (lifetime).
public fun total_repaid(vault: &LoanVault): u64 {
    vault.total_repaid
}

/// Get total fees earned.
public fun total_fees_earned(vault: &LoanVault): u64 {
    vault.total_fees_earned
}

/// Get active loan count.
public fun active_loans(vault: &LoanVault): u64 {
    vault.active_loans
}

/// Check if vault is paused.
public fun is_paused(vault: &LoanVault): bool {
    vault.paused
}

/// Get contract version.
public fun version(vault: &LoanVault): u64 {
    vault.version
}

/// Get config.
public fun config(vault: &LoanVault): LoanConfig {
    vault.config
}

/// Get max LTV.
public fun max_ltv_bps(config: &LoanConfig): u64 {
    config.max_ltv_bps
}

/// Get interest rate.
public fun interest_rate_bps(config: &LoanConfig): u64 {
    config.interest_rate_bps
}

/// Get loan ID from receipt.
public fun receipt_loan_id(receipt: &LoanReceipt): ID {
    receipt.loan_id
}

/// Get borrower from receipt.
public fun receipt_borrower(receipt: &LoanReceipt): address {
    receipt.borrower
}

/// Get pass ID from receipt.
public fun receipt_pass_id(receipt: &LoanReceipt): ID {
    receipt.pass_id
}

/// Get principal from receipt.
public fun receipt_principal(receipt: &LoanReceipt): u64 {
    receipt.principal
}

/// Get loan details.
public fun get_loan(vault: &LoanVault, loan_id: ID): (address, ID, u64, u64, u64, u64, u8) {
    let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
    (
        loan.borrower,
        loan.pass_id,
        loan.principal,
        loan.interest_accrued,
        loan.amount_repaid,
        loan.collateral_value,
        loan.status,
    )
}

/// Calculate current outstanding balance for a loan.
public fun get_outstanding(vault: &LoanVault, loan_id: ID): u64 {
    let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
    loan.principal + loan.interest_accrued - loan.amount_repaid
}

/// Calculate health factor for a loan.
/// Returns (numerator, denominator) to avoid floating point.
/// Health = (collateral × threshold) / outstanding
/// If numerator < denominator, loan is liquidatable.
public fun get_health_factor(
    vault: &LoanVault,
    loan_id: ID,
    capital_vault: &tide_core::capital_vault::CapitalVault,
): (u64, u64) {
    let loan = df::borrow<LoanKey, Loan>(&vault.id, LoanKey { loan_id });
    let pass = dof::borrow<PassKey, SupporterPass>(&vault.id, PassKey { pass_id: loan.pass_id });
    
    let collateral = calculate_collateral_value(pass, capital_vault);
    let outstanding = loan.principal + loan.interest_accrued - loan.amount_repaid;
    
    let threshold_value = (collateral * vault.config.liquidation_threshold_bps) / BPS_DENOMINATOR;
    
    (threshold_value, outstanding)
}

// === Internal Functions ===

/// Calculate collateral value using share proportion.
/// Conservative: uses original deposit proportion of total principal.
fun calculate_collateral_value(
    pass: &SupporterPass,
    capital_vault: &tide_core::capital_vault::CapitalVault,
): u64 {
    let total_shares = capital_vault.total_shares();
    if (total_shares == 0) {
        return 0
    };
    
    let total_principal = capital_vault.total_principal();
    let pass_shares = pass.shares();
    
    // value = (pass_shares / total_shares) * total_principal
    let value = ((pass_shares as u128) * (total_principal as u128)) / total_shares;
    (value as u64)
}

/// Accrue interest on a loan.
fun accrue_interest(
    loan: &mut Loan,
    interest_rate_bps: u64,
    ctx: &TxContext,
) {
    let current_ms = ctx.epoch_timestamp_ms();
    let elapsed_ms = current_ms - loan.last_update_ms;
    
    if (elapsed_ms == 0) {
        return
    };
    
    // Calculate outstanding balance (principal + interest - repaid)
    // Interest only accrues on unpaid portion
    let total_owed = loan.principal + loan.interest_accrued;
    if (loan.amount_repaid >= total_owed) {
        // Fully repaid, no interest to accrue
        loan.last_update_ms = current_ms;
        return
    };
    
    let outstanding = total_owed - loan.amount_repaid;
    
    // Simple interest: interest = outstanding × rate × time
    // Where time is fraction of year
    // interest = outstanding × rate_bps × elapsed_ms / (BPS_DENOMINATOR × MS_PER_YEAR)
    let new_interest = (
        (outstanding as u128) * 
        (interest_rate_bps as u128) * 
        (elapsed_ms as u128)
    ) / ((BPS_DENOMINATOR as u128) * (MS_PER_YEAR as u128));
    
    loan.interest_accrued = loan.interest_accrued + (new_interest as u64);
    loan.last_update_ms = current_ms;
}

// === Test Helpers ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}

#[test_only]
public fun destroy_receipt_for_testing(receipt: LoanReceipt) {
    let LoanReceipt { id, loan_id: _, borrower: _, pass_id: _, principal: _ } = receipt;
    id.delete();
}
