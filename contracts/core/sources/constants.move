/// Shared constants for Tide Core.
module tide_core::constants;

// === Precision ===

/// 18 decimal fixed-point precision for share calculations.
/// This ensures small reward amounts (< 1 SUI) still update the reward index.
public macro fun precision(): u128 { 1_000_000_000_000_000_000 }

/// Basis points denominator (10000 = 100%).
public macro fun max_bps(): u64 { 10_000 }

// === Version ===

/// Protocol version for upgrade compatibility.
/// v2: Fixed share calculation (no PRECISION scaling) + 1e18 precision for reward index
/// v3: Productive capital - stake locked capital from CapitalVault
public macro fun version(): u64 { 3 }

// === Fee Constants ===

/// Raise fee in basis points (1% = 100 bps).
/// Deducted from total raised capital before first tranche release.
public macro fun raise_fee_bps(): u64 { 100 }

/// Staking reward split for backers in basis points (80% = 8000 bps).
/// Remaining 20% goes to Tide Treasury.
public macro fun staking_backer_bps(): u64 { 8_000 }

/// Staking reward split for treasury in basis points (20% = 2000 bps).
public macro fun staking_treasury_bps(): u64 { 2_000 }

// === Capital Release Schedule Constants ===

/// Initial release at finalization in basis points (20% = 2000 bps).
public macro fun initial_release_bps(): u64 { 2_000 }

/// Remaining capital released over monthly tranches (80% = 8000 bps).
public macro fun monthly_release_bps(): u64 { 8_000 }

/// Number of monthly tranches for remaining capital.
public macro fun monthly_tranche_count(): u64 { 12 }

/// Duration of each tranche period in milliseconds (30 days).
/// 30 days = 30 * 24 * 60 * 60 * 1000 = 2,592,000,000 ms
public macro fun tranche_interval_ms(): u64 { 2_592_000_000 }

/// Total schedule duration in months.
public macro fun schedule_duration_months(): u64 { 12 }

// === Deposit Limits ===

/// Minimum deposit amount in MIST (1 SUI = 1,000,000,000 MIST).
/// Prevents spam attacks and dust deposits.
public macro fun min_deposit(): u64 { 1_000_000_000 }

// === Lifecycle States ===

/// Listing is in draft mode, config editable, no deposits.
public macro fun state_draft(): u8 { 0 }

/// Listing is active, accepting deposits.
public macro fun state_active(): u8 { 1 }

/// Listing is finalized, no new deposits, releases continue.
public macro fun state_finalized(): u8 { 2 }

/// Listing is completed, all released, claims only.
public macro fun state_completed(): u8 { 3 }
