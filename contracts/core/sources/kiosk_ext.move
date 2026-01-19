/// Kiosk extension for SupporterPass.
/// 
/// Enables claiming rewards while a SupporterPass is listed on
/// Kiosk-based NFT marketplaces (BlueMove, Clutchy, etc.).
/// 
/// ## How It Works
/// 
/// When a pass is placed in a Kiosk, the owner can still claim rewards
/// by borrowing the pass mutably using their KioskOwnerCap, claiming,
/// and returning it to the Kiosk - all in a single transaction.
/// 
/// ## Usage
/// 
/// ```move
/// // Claim from a single pass in your Kiosk
/// let reward = kiosk_ext::claim_from_kiosk(
///     &listing, &tide, &mut reward_vault,
///     &mut kiosk, &kiosk_cap, pass_id,
///     ctx
/// );
/// ```
/// 
/// ## Marketplace Compatibility
/// 
/// This works with any Kiosk-based marketplace because:
/// 1. The pass stays in the Kiosk (listing not affected)
/// 2. Only the KioskOwnerCap holder can claim
/// 3. The pass is borrowed and returned in the same transaction
module tide_core::kiosk_ext;

use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
use sui::coin::Coin;
use sui::sui::SUI;

use tide_core::listing::Listing;
use tide_core::tide::Tide;
use tide_core::reward_vault::RewardVault;
use tide_core::supporter_pass::SupporterPass;
use tide_core::errors;
use tide_core::events;

// === Public Functions ===

/// Claim rewards for a SupporterPass that is held in a Kiosk.
/// 
/// This allows pass holders to claim rewards even while their pass
/// is listed for sale on a Kiosk-based marketplace.
/// 
/// Requirements:
/// - Caller must own the KioskOwnerCap for the Kiosk
/// - Pass must exist in the Kiosk
/// - Pass must belong to the specified listing
/// 
/// Note: Claims are allowed even when listing is paused (per spec).
public fun claim_from_kiosk(
    listing: &Listing,
    _tide: &Tide,
    reward_vault: &mut RewardVault,
    kiosk: &mut Kiosk,
    kiosk_cap: &KioskOwnerCap,
    pass_id: ID,
    ctx: &mut TxContext,
): Coin<SUI> {
    // Borrow the pass mutably from the Kiosk
    let pass = kiosk::borrow_mut<SupporterPass>(kiosk, kiosk_cap, pass_id);
    
    // Verify pass belongs to this listing
    pass.assert_listing(listing.id());
    
    // Calculate claimable amount
    let claimable = reward_vault.calculate_claimable(
        pass.shares(),
        pass.claim_index(),
    );
    
    assert!(claimable > 0, errors::nothing_to_claim());
    
    // Capture old index for event
    let old_claim_index = pass.claim_index();
    let new_claim_index = reward_vault.global_index();
    
    // Update pass cursor
    pass.update_claim_index(new_claim_index);
    
    // Track lifetime claimed
    pass.add_claimed(claimable);
    
    // Withdraw from vault
    let coin = reward_vault.withdraw(claimable, ctx);
    
    // Emit claim event (same as regular claim for indexing consistency)
    events::emit_claimed(
        listing.id(),
        pass_id,
        ctx.sender(),
        claimable,
        pass.shares(),
        old_claim_index,
        new_claim_index,
        ctx.epoch(),
    );
    
    // Pass automatically returns to Kiosk when borrow ends
    coin
}

/// Claim rewards for multiple SupporterPasses held in the same Kiosk.
/// 
/// Convenience function for users with multiple passes in one Kiosk.
/// Skips passes with nothing to claim (no error).
/// 
/// Returns: Single merged Coin<SUI> with total claimed amount.
public fun claim_many_from_kiosk(
    listing: &Listing,
    _tide: &Tide,
    reward_vault: &mut RewardVault,
    kiosk: &mut Kiosk,
    kiosk_cap: &KioskOwnerCap,
    pass_ids: vector<ID>,
    ctx: &mut TxContext,
): Coin<SUI> {
    use sui::coin;
    
    let mut total = coin::zero<SUI>(ctx);
    let len = pass_ids.length();
    let mut i = 0;
    let mut claimed_count: u64 = 0;
    let mut total_amount: u64 = 0;
    
    while (i < len) {
        let pass_id = *pass_ids.borrow(i);
        
        // Borrow pass from Kiosk
        let pass = kiosk::borrow_mut<SupporterPass>(kiosk, kiosk_cap, pass_id);
        
        // Verify pass belongs to this listing
        pass.assert_listing(listing.id());
        
        let claimable = reward_vault.calculate_claimable(
            pass.shares(),
            pass.claim_index(),
        );
        
        // Skip passes with nothing to claim
        if (claimable > 0) {
            let old_claim_index = pass.claim_index();
            let new_claim_index = reward_vault.global_index();
            
            pass.update_claim_index(new_claim_index);
            pass.add_claimed(claimable);
            
            let coin = reward_vault.withdraw(claimable, ctx);
            total.join(coin);
            
            events::emit_claimed(
                listing.id(),
                pass_id,
                ctx.sender(),
                claimable,
                pass.shares(),
                old_claim_index,
                new_claim_index,
                ctx.epoch(),
            );
            
            claimed_count = claimed_count + 1;
            total_amount = total_amount + claimable;
        };
        
        // Pass returns to Kiosk when borrow ends
        i = i + 1;
    };
    
    // Emit batch summary event
    if (claimed_count > 0) {
        events::emit_batch_claimed(
            listing.id(),
            ctx.sender(),
            claimed_count,
            total_amount,
            ctx.epoch(),
        );
    };
    
    total
}

// === View Functions ===

/// Check if a pass in a Kiosk has claimable rewards.
/// Useful for frontends to show claimable amounts.
public fun claimable_in_kiosk(
    reward_vault: &RewardVault,
    kiosk: &Kiosk,
    kiosk_cap: &KioskOwnerCap,
    pass_id: ID,
): u64 {
    let pass = kiosk::borrow<SupporterPass>(kiosk, kiosk_cap, pass_id);
    reward_vault.calculate_claimable(pass.shares(), pass.claim_index())
}
