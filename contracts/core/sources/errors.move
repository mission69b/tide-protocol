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

