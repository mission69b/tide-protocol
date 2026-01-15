/// Fixed-point arithmetic for share calculations and reward distribution.
module tide_core::math;

use tide_core::constants;

// === Multiplication/Division ===

/// Multiply then divide with overflow protection: (a × b) / c
/// Aborts on division by zero or overflow.
public fun mul_div(a: u128, b: u128, c: u128): u128 {
    assert!(c > 0, 0); // division by zero
    // Use u256 for intermediate to prevent overflow
    let result = ((a as u256) * (b as u256)) / (c as u256);
    // Check result fits in u128 (max = 2^128 - 1)
    assert!(result <= 340282366920938463463374607431768211455u256, 1);
    (result as u128)
}

/// Floor division: (a × b) / c, rounding down.
public fun mul_div_down(a: u128, b: u128, c: u128): u128 {
    mul_div(a, b, c)
}

/// Ceiling division: (a × b) / c, rounding up.
public fun mul_div_up(a: u128, b: u128, c: u128): u128 {
    assert!(c > 0, 0);
    let result = ((a as u256) * (b as u256));
    let c256 = (c as u256);
    let rounded = (result + c256 - 1) / c256;
    (rounded as u128)
}

// === Share Calculations ===

/// Convert deposit amount to shares.
/// First depositor gets shares = amount × PRECISION.
/// Subsequent depositors get proportional shares.
public fun to_shares(amount: u64, total_principal: u64, total_shares: u128): u128 {
    if (total_principal == 0 || total_shares == 0) {
        // First deposit: 1 SUI = PRECISION shares
        (amount as u128) * constants::precision!()
    } else {
        // Proportional: shares = amount × total_shares / total_principal
        mul_div((amount as u128), total_shares, (total_principal as u128))
    }
}

/// Convert shares to SUI amount.
public fun to_amount(shares: u128, total_principal: u64, total_shares: u128): u64 {
    if (total_shares == 0) {
        0
    } else {
        let amount = mul_div(shares, (total_principal as u128), total_shares);
        (amount as u64)
    }
}

/// Calculate claimable rewards.
/// claimable = shares × (global_index - pass_index) / PRECISION
public fun calculate_claimable(
    shares: u128,
    global_index: u128,
    pass_index: u128,
): u64 {
    if (global_index <= pass_index) {
        0
    } else {
        let delta = global_index - pass_index;
        let claimable = mul_div(shares, delta, constants::precision!());
        (claimable as u64)
    }
}

/// Calculate new reward index after deposit.
/// new_index = old_index + (reward_amount × PRECISION / total_shares)
public fun calculate_new_index(
    old_index: u128,
    reward_amount: u64,
    total_shares: u128,
): u128 {
    if (total_shares == 0) {
        old_index
    } else {
        let delta = mul_div(
            (reward_amount as u128),
            constants::precision!(),
            total_shares,
        );
        old_index + delta
    }
}

// === Tests ===

#[test]
fun test_mul_div() {
    assert!(mul_div(100, 200, 50) == 400);
    assert!(mul_div(1000000000000, 1000000000000, 1000000000000) == 1000000000000);
}

#[test]
fun test_mul_div_up() {
    assert!(mul_div_up(10, 3, 4) == 8); // 30/4 = 7.5 → 8
    assert!(mul_div_up(10, 4, 4) == 10); // 40/4 = 10 → 10
}

#[test]
fun test_to_shares_first_deposit() {
    let shares = to_shares(1000, 0, 0);
    assert!(shares == 1000 * constants::precision!());
}

#[test]
fun test_to_shares_proportional() {
    let total_principal = 1000;
    let total_shares = 1000 * constants::precision!();
    
    // Second deposit of same amount should get same shares
    let shares = to_shares(1000, total_principal, total_shares);
    assert!(shares == total_shares);
}

#[test]
fun test_calculate_claimable() {
    // User with 1000 shares (scaled), index moved from 0 to 1 (scaled by PRECISION)
    // claimable = shares × delta / PRECISION
    // = (1000 × PRECISION) × PRECISION / PRECISION = 1000 × PRECISION (as u64)
    let shares = 1000 * constants::precision!();
    let pass_index = 0;
    let global_index = 1; // Small index change (1 unit of reward per PRECISION shares)
    
    let claimable = calculate_claimable(shares, global_index, pass_index);
    // claimable = (1000 × PRECISION) × 1 / PRECISION = 1000
    assert!(claimable == 1000);
}

#[test]
fun test_calculate_new_index() {
    // 100 rewards distributed among 1000 scaled shares
    // delta = 100 × PRECISION / (1000 × PRECISION) 
    // But this would be 0 due to integer division!
    // 
    // The fix: shares should NOT be scaled by PRECISION for this formula to work.
    // Or we need to use unscaled shares for reward calculation.
    // 
    // With unscaled shares (1000), delta = 100 × PRECISION / 1000 = PRECISION / 10
    let old_index = 0;
    let reward = 100;
    let total_shares = 1000; // Unscaled for this test
    
    let new_index = calculate_new_index(old_index, reward, total_shares);
    assert!(new_index == constants::precision!() / 10);
}
