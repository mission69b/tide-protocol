/// Display configuration for Tide Core objects.
/// 
/// This module handles presentation-only metadata using sui::display.
/// Display is non-economic and MUST NOT affect reward calculations.
/// 
/// ## Multi-Listing Support
/// 
/// Since there's only ONE Display<SupporterPass> globally, we use
/// field placeholders to enable listing-specific rendering:
/// 
/// - `{id}` — Object ID of the SupporterPass
/// - `{listing_id}` — ID of the listing this pass belongs to
/// - `{shares}` — Number of shares held
/// 
/// The off-chain renderer uses `listing_id` to look up listing-specific
/// metadata (name, branding, issuer info) and render accordingly.
/// 
/// Example flow:
/// 1. Wallet requests image for SupporterPass
/// 2. Sui substitutes: "https://api.tide.xyz/pass/{listing_id}/{id}/image"
///    → "https://api.tide.xyz/pass/0x123.../0x456.../image"
/// 3. Tide API looks up listing 0x123... metadata
/// 4. Renders pass image with correct branding (FAITH, future listings, etc.)
#[allow(lint(self_transfer))]
module tide_core::display;

use sui::display;
use sui::package::Publisher;

use tide_core::supporter_pass::SupporterPass;

// === Constants ===

// Generic display values using placeholders for multi-listing support
// {listing_id} enables the off-chain renderer to customize per listing
const DEFAULT_NAME: vector<u8> = b"Tide Supporter Pass";
const DEFAULT_DESCRIPTION: vector<u8> = b"A transferable position representing {shares} shares in a Tide listing. Entitles holder to claim rewards from protocol revenue and staking yield.";

// URLs use {listing_id} to enable listing-specific rendering
// The off-chain API looks up listing metadata to determine branding
const DEFAULT_IMAGE_URL: vector<u8> = b"https://api.tide.xyz/pass/{listing_id}/{id}/image.svg";
const DEFAULT_LINK: vector<u8> = b"https://app.tide.xyz/listing/{listing_id}/pass/{id}";
const DEFAULT_PROJECT_URL: vector<u8> = b"https://tide.xyz";

// === Display Setup ===

/// Initialize Display for SupporterPass.
/// Called during package deployment with Publisher.
/// 
/// Display fields:
/// - name: Human-readable name
/// - description: What this NFT represents (uses {shares} placeholder)
/// - image_url: URL to SVG/image (uses {listing_id} and {id} for dynamic rendering)
/// - link: URL to view details (uses {listing_id} and {id})
/// - project_url: Project homepage
/// 
/// Placeholders are replaced by Sui with actual field values:
/// - {id} → Object ID
/// - {listing_id} → Listing this pass belongs to
/// - {shares} → Number of shares
/// 
/// The off-chain renderer uses listing_id to look up listing-specific
/// metadata (issuer name, branding, colors, etc.) and render accordingly.
public fun setup_supporter_pass_display(
    publisher: &Publisher,
    ctx: &mut TxContext,
): display::Display<SupporterPass> {
    let mut d = display::new<SupporterPass>(publisher, ctx);
    
    d.add(b"name".to_string(), DEFAULT_NAME.to_string());
    d.add(b"description".to_string(), DEFAULT_DESCRIPTION.to_string());
    d.add(b"image_url".to_string(), DEFAULT_IMAGE_URL.to_string());
    d.add(b"link".to_string(), DEFAULT_LINK.to_string());
    d.add(b"project_url".to_string(), DEFAULT_PROJECT_URL.to_string());
    
    // Publish the display
    d.update_version();
    
    d
}

/// Create Display and transfer to sender (convenience function).
/// Use this in init() or when setting up the protocol.
public fun create_and_keep_supporter_pass_display(
    publisher: &Publisher,
    ctx: &mut TxContext,
) {
    let d = setup_supporter_pass_display(publisher, ctx);
    transfer::public_transfer(d, ctx.sender());
}

// === Display Updates ===
// These require ownership of the Display object (held by protocol admin)

/// Update the image URL template for SupporterPass Display.
/// Should include {listing_id} and {id} placeholders for multi-listing support.
public fun update_image_url(
    d: &mut display::Display<SupporterPass>,
    new_url: vector<u8>,
) {
    d.edit(b"image_url".to_string(), new_url.to_string());
    d.update_version();
}

/// Update the link URL template for SupporterPass Display.
/// Should include {listing_id} and {id} placeholders.
public fun update_link(
    d: &mut display::Display<SupporterPass>,
    new_url: vector<u8>,
) {
    d.edit(b"link".to_string(), new_url.to_string());
    d.update_version();
}

/// Update the description for SupporterPass Display.
/// Can use {shares} placeholder.
public fun update_description(
    d: &mut display::Display<SupporterPass>,
    new_description: vector<u8>,
) {
    d.edit(b"description".to_string(), new_description.to_string());
    d.update_version();
}

/// Update the name for SupporterPass Display.
public fun update_name(
    d: &mut display::Display<SupporterPass>,
    new_name: vector<u8>,
) {
    d.edit(b"name".to_string(), new_name.to_string());
    d.update_version();
}

/// Update the project URL for SupporterPass Display.
public fun update_project_url(
    d: &mut display::Display<SupporterPass>,
    new_url: vector<u8>,
) {
    d.edit(b"project_url".to_string(), new_url.to_string());
    d.update_version();
}
