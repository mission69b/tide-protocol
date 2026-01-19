/// Canonical error codes for Tide Core.
#[allow(unused_const)]
module tide_core::errors;

// === Error Constants ===

#[error]
const ENotActive: vector<u8> = b"Listing is not in Active state";

#[error]
const EPaused: vector<u8> = b"Protocol is paused";

#[error]
const EInvalidAmount: vector<u8> = b"Invalid or zero amount";

#[error]
const ENothingToClaim: vector<u8> = b"No rewards to claim";

#[error]
const ENotAuthorized: vector<u8> = b"Caller lacks required capability";

#[error]
const EInvalidState: vector<u8> = b"Invalid state transition";

#[error]
const ETrancheNotReady: vector<u8> = b"Tranche not yet releasable";

#[error]
const EAlreadyReleased: vector<u8> = b"Tranche already released";

#[error]
const EInsufficientBalance: vector<u8> = b"Insufficient balance for operation";

#[error]
const EStakingLocked: vector<u8> = b"Capital is staked and cannot be withdrawn yet";

#[error]
const EWrongListing: vector<u8> = b"SupporterPass does not belong to this listing";

#[error]
const ENotDraft: vector<u8> = b"Listing is not in Draft state";

#[error]
const EVersionMismatch: vector<u8> = b"Version mismatch";

#[error]
const EAllTranchesReleased: vector<u8> = b"All tranches already released";

#[error]
const EBelowMinimum: vector<u8> = b"Deposit amount below minimum (1 SUI)";

#[error]
const ENotCancelled: vector<u8> = b"Listing is not in Cancelled state";

#[error]
const ECannotCancel: vector<u8> = b"Listing cannot be cancelled in this state";

#[error]
const EStakedCapital: vector<u8> = b"Cannot cancel while capital is staked - unstake first";

#[error]
const EAlreadyRefunded: vector<u8> = b"Pass has already been refunded";

// === Public Functions (for cross-package use) ===

public fun not_active(): u64 { 0 }
public fun paused(): u64 { 1 }
public fun invalid_amount(): u64 { 2 }
public fun nothing_to_claim(): u64 { 3 }
public fun not_authorized(): u64 { 4 }
public fun invalid_state(): u64 { 5 }
public fun tranche_not_ready(): u64 { 6 }
public fun already_released(): u64 { 7 }
public fun insufficient_balance(): u64 { 8 }
public fun staking_locked(): u64 { 9 }
public fun wrong_listing(): u64 { 10 }
public fun not_draft(): u64 { 11 }
public fun version_mismatch(): u64 { 12 }
public fun all_tranches_released(): u64 { 13 }
public fun below_minimum(): u64 { 14 }
public fun not_cancelled(): u64 { 15 }
public fun cannot_cancel(): u64 { 16 }
public fun staked_capital(): u64 { 17 }
public fun already_refunded(): u64 { 18 }

// === Test Constants (for expected_failure attributes) ===

#[test_only]
const ENOT_ACTIVE: u64 = 0;
#[test_only]
const EPAUSED: u64 = 1;
#[test_only]
const EINVALID_AMOUNT: u64 = 2;
#[test_only]
const ENOTHING_TO_CLAIM: u64 = 3;
#[test_only]
const ENOT_AUTHORIZED: u64 = 4;
#[test_only]
const EINVALID_STATE: u64 = 5;
#[test_only]
const ETRANCHE_NOT_READY: u64 = 6;
#[test_only]
const EALREADY_RELEASED: u64 = 7;
#[test_only]
const EINSUFFICIENT_BALANCE: u64 = 8;
#[test_only]
const ESTAKING_LOCKED: u64 = 9;
#[test_only]
const EWRONG_LISTING: u64 = 10;
#[test_only]
const ENOT_DRAFT: u64 = 11;
#[test_only]
const EVERSION_MISMATCH: u64 = 12;
#[test_only]
const EALL_TRANCHES_RELEASED: u64 = 13;
#[test_only]
const EBELOW_MINIMUM: u64 = 14;
#[test_only]
const ENOT_CANCELLED: u64 = 15;
#[test_only]
const ECANNOT_CANCEL: u64 = 16;
#[test_only]
const ESTAKED_CAPITAL: u64 = 17;
#[test_only]
const EALREADY_REFUNDED: u64 = 18;
