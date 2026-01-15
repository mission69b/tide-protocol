/// Shared constants for Tide Core.
module tide_core::constants;

// === Precision ===

/// 12 decimal fixed-point precision for share calculations.
public macro fun precision(): u128 { 1_000_000_000_000 }

/// Basis points denominator (10000 = 100%).
public macro fun max_bps(): u64 { 10_000 }

// === Version ===

/// Protocol version for upgrade compatibility.
public macro fun version(): u64 { 1 }

// === Fee Constants ===

/// Raise fee in basis points (1% = 100 bps).
/// Deducted from total raised capital before first tranche release.
public macro fun raise_fee_bps(): u64 { 100 }

/// Staking reward split for backers in basis points (80% = 8000 bps).
/// Remaining 20% goes to Tide Treasury.
public macro fun staking_backer_bps(): u64 { 8_000 }

/// Staking reward split for treasury in basis points (20% = 2000 bps).
public macro fun staking_treasury_bps(): u64 { 2_000 }

// === Lifecycle States ===

/// Listing is in draft mode, config editable, no deposits.
public macro fun state_draft(): u8 { 0 }

/// Listing is active, accepting deposits.
public macro fun state_active(): u8 { 1 }

/// Listing is finalized, no new deposits, releases continue.
public macro fun state_finalized(): u8 { 2 }

/// Listing is completed, all released, claims only.
public macro fun state_completed(): u8 { 3 }
