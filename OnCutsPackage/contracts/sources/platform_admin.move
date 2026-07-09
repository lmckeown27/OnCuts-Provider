/// CampusCuts Platform Admin Module
/// 
/// This module provides administrative functions:
/// 1. Access control (add/remove admins)
/// 2. Dispute resolution
/// 3. Platform fee management & withdrawal
/// 4. Emergency pause/unpause
/// 5. Platform configuration
/// 
/// Only platform admin can call these functions.
module campus_cuts::platform_admin {
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_std::table::{Self, Table};
    use aptos_std::event::{Self, EventHandle};
    use campus_cuts::user_accounts;
    use campus_cuts::bookings;

    // ═══════════════════════════════════════════════════════════
    //  ERRORS
    // ═══════════════════════════════════════════════════════════

    const E_NOT_AUTHORIZED: u64 = 1;
    const E_PLATFORM_NOT_INITIALIZED: u64 = 2;
    const E_ALREADY_ADMIN: u64 = 3;
    const E_NOT_ADMIN: u64 = 4;
    const E_CANNOT_REMOVE_ROOT_ADMIN: u64 = 5;
    const E_PLATFORM_PAUSED: u64 = 6;
    const E_DISPUTE_NOT_FOUND: u64 = 7;
    const E_DISPUTE_ALREADY_RESOLVED: u64 = 8;
    const E_INSUFFICIENT_FEES: u64 = 9;

    // ═══════════════════════════════════════════════════════════
    //  CONSTANTS
    // ═══════════════════════════════════════════════════════════

    const DISPUTE_STATUS_OPEN: u8 = 0;
    const DISPUTE_STATUS_RESOLVED_REFUND: u8 = 1;
    const DISPUTE_STATUS_RESOLVED_RELEASE: u8 = 2;
    const DISPUTE_STATUS_DISMISSED: u8 = 3;

    // ═══════════════════════════════════════════════════════════
    //  DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════

    /// Platform configuration
    struct PlatformConfig has key {
        // Admin management
        root_admin: address,                 // Cannot be removed
        admins: vector<address>,             // Additional admins
        
        // Fee management
        platform_fee_bps: u64,               // Current platform fee (basis points)
        accumulated_fees: u64,               // Total fees collected (in octas)
        total_fees_withdrawn: u64,           // Lifetime withdrawals
        
        // Emergency controls
        is_paused: bool,                     // Global pause switch
        paused_at: u64,                      // Timestamp of pause
        paused_reason: String,               // Why paused
        
        // Stats
        total_disputes_handled: u64,
        total_refunds_issued: u64,
        total_bookings_created: u64,
        
        // Events
        admin_added_events: EventHandle<AdminAddedEvent>,
        admin_removed_events: EventHandle<AdminRemovedEvent>,
        dispute_resolved_events: EventHandle<DisputeResolvedEvent>,
        fees_withdrawn_events: EventHandle<FeesWithdrawnEvent>,
        platform_paused_events: EventHandle<PlatformPausedEvent>,
        platform_unpaused_events: EventHandle<PlatformUnpausedEvent>,
    }

    /// Dispute record
    struct Dispute has store {
        id: u64,
        booking_id: u64,
        filed_by: address,              // Who filed (student or barber)
        against: address,               // The other party
        reason: String,
        evidence_cid: String,           // IPFS CID for evidence
        status: u8,
        resolution: String,             // Admin's resolution notes
        resolved_at: u64,
        resolved_by: address,
        created_at: u64,
    }

    /// Disputes table
    struct DisputeRegistry has key {
        disputes: Table<u64, Dispute>,
        next_dispute_id: u64,
        open_disputes: vector<u64>,
    }

    // ═══════════════════════════════════════════════════════════
    //  EVENTS
    // ═══════════════════════════════════════════════════════════

    struct AdminAddedEvent has drop, store {
        admin_address: address,
        added_by: address,
        timestamp: u64,
    }

    struct AdminRemovedEvent has drop, store {
        admin_address: address,
        removed_by: address,
        timestamp: u64,
    }

    struct DisputeResolvedEvent has drop, store {
        dispute_id: u64,
        booking_id: u64,
        resolution: u8,
        resolved_by: address,
        timestamp: u64,
    }

    struct FeesWithdrawnEvent has drop, store {
        amount: u64,
        withdrawn_to: address,
        withdrawn_by: address,
        timestamp: u64,
    }

    struct PlatformPausedEvent has drop, store {
        reason: String,
        paused_by: address,
        timestamp: u64,
    }

    struct PlatformUnpausedEvent has drop, store {
        unpaused_by: address,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════
    //  INITIALIZATION
    // ═══════════════════════════════════════════════════════════

    /// Initialize platform admin (called once by deployer)
    public entry fun initialize(platform: &signer) {
        let platform_addr = signer::address_of(platform);
        
        move_to(platform, PlatformConfig {
            root_admin: platform_addr,
            admins: vector::empty<address>(),
            platform_fee_bps: 500, // 5% default
            accumulated_fees: 0,
            total_fees_withdrawn: 0,
            is_paused: false,
            paused_at: 0,
            paused_reason: std::string::utf8(b""),
            total_disputes_handled: 0,
            total_refunds_issued: 0,
            total_bookings_created: 0,
            admin_added_events: account::new_event_handle<AdminAddedEvent>(platform),
            admin_removed_events: account::new_event_handle<AdminRemovedEvent>(platform),
            dispute_resolved_events: account::new_event_handle<DisputeResolvedEvent>(platform),
            fees_withdrawn_events: account::new_event_handle<FeesWithdrawnEvent>(platform),
            platform_paused_events: account::new_event_handle<PlatformPausedEvent>(platform),
            platform_unpaused_events: account::new_event_handle<PlatformUnpausedEvent>(platform),
        });

        move_to(platform, DisputeRegistry {
            disputes: table::new(),
            next_dispute_id: 1,
            open_disputes: vector::empty<u64>(),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  ADMIN MANAGEMENT
    // ═══════════════════════════════════════════════════════════

    /// Add a new admin (only root admin can call)
    public entry fun add_admin(
        caller: &signer,
        new_admin: address,
    ) acquires PlatformConfig {
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        let caller_addr = signer::address_of(caller);
        
        // Only root admin can add admins
        assert!(caller_addr == config.root_admin, E_NOT_AUTHORIZED);
        
        // Check not already admin
        assert!(!vector::contains(&config.admins, &new_admin), E_ALREADY_ADMIN);
        assert!(new_admin != config.root_admin, E_ALREADY_ADMIN);
        
        vector::push_back(&mut config.admins, new_admin);
        
        event::emit_event(&mut config.admin_added_events, AdminAddedEvent {
            admin_address: new_admin,
            added_by: caller_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Remove an admin (only root admin can call)
    public entry fun remove_admin(
        caller: &signer,
        admin_to_remove: address,
    ) acquires PlatformConfig {
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        let caller_addr = signer::address_of(caller);
        
        // Only root admin can remove admins
        assert!(caller_addr == config.root_admin, E_NOT_AUTHORIZED);
        
        // Cannot remove root admin
        assert!(admin_to_remove != config.root_admin, E_CANNOT_REMOVE_ROOT_ADMIN);
        
        // Find and remove
        let (found, index) = vector::index_of(&config.admins, &admin_to_remove);
        assert!(found, E_NOT_ADMIN);
        
        vector::remove(&mut config.admins, index);
        
        event::emit_event(&mut config.admin_removed_events, AdminRemovedEvent {
            admin_address: admin_to_remove,
            removed_by: caller_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  DISPUTE RESOLUTION
    // ═══════════════════════════════════════════════════════════

    /// File a dispute (student or barber)
    public entry fun file_dispute(
        caller: &signer,
        booking_id: u64,
        against: address,
        reason: String,
        evidence_cid: String,
    ) acquires DisputeRegistry {
        let registry = borrow_global_mut<DisputeRegistry>(@campus_cuts);
        let caller_addr = signer::address_of(caller);
        
        let dispute_id = registry.next_dispute_id;
        registry.next_dispute_id = dispute_id + 1;
        
        let dispute = Dispute {
            id: dispute_id,
            booking_id,
            filed_by: caller_addr,
            against,
            reason,
            evidence_cid,
            status: DISPUTE_STATUS_OPEN,
            resolution: std::string::utf8(b""),
            resolved_at: 0,
            resolved_by: @0x0,
            created_at: timestamp::now_seconds(),
        };
        
        table::add(&mut registry.disputes, dispute_id, dispute);
        vector::push_back(&mut registry.open_disputes, dispute_id);
    }

    /// Resolve dispute with refund (admin only)
    public entry fun resolve_dispute_refund(
        admin: &signer,
        dispute_id: u64,
        resolution_notes: String,
    ) acquires PlatformConfig, DisputeRegistry {
        assert_is_admin(admin);
        
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        let registry = borrow_global_mut<DisputeRegistry>(@campus_cuts);
        
        assert!(table::contains(&registry.disputes, dispute_id), E_DISPUTE_NOT_FOUND);
        let dispute = table::borrow_mut(&mut registry.disputes, dispute_id);
        
        assert!(dispute.status == DISPUTE_STATUS_OPEN, E_DISPUTE_ALREADY_RESOLVED);
        
        // Update dispute
        dispute.status = DISPUTE_STATUS_RESOLVED_REFUND;
        dispute.resolution = resolution_notes;
        dispute.resolved_at = timestamp::now_seconds();
        dispute.resolved_by = signer::address_of(admin);
        
        // Remove from open disputes
        let (found, index) = vector::index_of(&registry.open_disputes, &dispute_id);
        if (found) {
            vector::remove(&mut registry.open_disputes, index);
        };
        
        // Update stats
        config.total_disputes_handled = config.total_disputes_handled + 1;
        config.total_refunds_issued = config.total_refunds_issued + 1;
        
        // Emit event
        event::emit_event(&mut config.dispute_resolved_events, DisputeResolvedEvent {
            dispute_id,
            booking_id: dispute.booking_id,
            resolution: DISPUTE_STATUS_RESOLVED_REFUND,
            resolved_by: signer::address_of(admin),
            timestamp: timestamp::now_seconds(),
        });
        
        // TODO: Trigger refund via bookings module
    }

    /// Resolve dispute by releasing to barber (admin only)
    public entry fun resolve_dispute_release(
        admin: &signer,
        dispute_id: u64,
        resolution_notes: String,
    ) acquires PlatformConfig, DisputeRegistry {
        assert_is_admin(admin);
        
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        let registry = borrow_global_mut<DisputeRegistry>(@campus_cuts);
        
        assert!(table::contains(&registry.disputes, dispute_id), E_DISPUTE_NOT_FOUND);
        let dispute = table::borrow_mut(&mut registry.disputes, dispute_id);
        
        assert!(dispute.status == DISPUTE_STATUS_OPEN, E_DISPUTE_ALREADY_RESOLVED);
        
        // Update dispute
        dispute.status = DISPUTE_STATUS_RESOLVED_RELEASE;
        dispute.resolution = resolution_notes;
        dispute.resolved_at = timestamp::now_seconds();
        dispute.resolved_by = signer::address_of(admin);
        
        // Remove from open disputes
        let (found, index) = vector::index_of(&registry.open_disputes, &dispute_id);
        if (found) {
            vector::remove(&mut registry.open_disputes, index);
        };
        
        // Update stats
        config.total_disputes_handled = config.total_disputes_handled + 1;
        
        // Emit event
        event::emit_event(&mut config.dispute_resolved_events, DisputeResolvedEvent {
            dispute_id,
            booking_id: dispute.booking_id,
            resolution: DISPUTE_STATUS_RESOLVED_RELEASE,
            resolved_by: signer::address_of(admin),
            timestamp: timestamp::now_seconds(),
        });
        
        // TODO: Trigger release via bookings module
    }

    /// Dismiss dispute (admin only)
    public entry fun dismiss_dispute(
        admin: &signer,
        dispute_id: u64,
        resolution_notes: String,
    ) acquires PlatformConfig, DisputeRegistry {
        assert_is_admin(admin);
        
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        let registry = borrow_global_mut<DisputeRegistry>(@campus_cuts);
        
        assert!(table::contains(&registry.disputes, dispute_id), E_DISPUTE_NOT_FOUND);
        let dispute = table::borrow_mut(&mut registry.disputes, dispute_id);
        
        assert!(dispute.status == DISPUTE_STATUS_OPEN, E_DISPUTE_ALREADY_RESOLVED);
        
        // Update dispute
        dispute.status = DISPUTE_STATUS_DISMISSED;
        dispute.resolution = resolution_notes;
        dispute.resolved_at = timestamp::now_seconds();
        dispute.resolved_by = signer::address_of(admin);
        
        // Remove from open disputes
        let (found, index) = vector::index_of(&registry.open_disputes, &dispute_id);
        if (found) {
            vector::remove(&mut registry.open_disputes, index);
        };
        
        // Update stats
        config.total_disputes_handled = config.total_disputes_handled + 1;
        
        // Emit event
        event::emit_event(&mut config.dispute_resolved_events, DisputeResolvedEvent {
            dispute_id,
            booking_id: dispute.booking_id,
            resolution: DISPUTE_STATUS_DISMISSED,
            resolved_by: signer::address_of(admin),
            timestamp: timestamp::now_seconds(),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  PLATFORM FEE MANAGEMENT
    // ═══════════════════════════════════════════════════════════

    /// Record platform fee (called by bookings module)
    public fun record_fee(amount: u64) acquires PlatformConfig {
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        config.accumulated_fees = config.accumulated_fees + amount;
    }

    /// Withdraw platform fees (admin only)
    public entry fun withdraw_fees(
        admin: &signer,
        amount: u64,
        recipient: address,
    ) acquires PlatformConfig {
        assert_is_admin(admin);
        
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        
        // Check sufficient balance
        assert!(config.accumulated_fees >= amount, E_INSUFFICIENT_FEES);
        
        // Deduct from accumulated
        config.accumulated_fees = config.accumulated_fees - amount;
        config.total_fees_withdrawn = config.total_fees_withdrawn + amount;
        
        // Transfer APT (assuming fees are in APT)
        coin::transfer<AptosCoin>(admin, recipient, amount);
        
        // Emit event
        event::emit_event(&mut config.fees_withdrawn_events, FeesWithdrawnEvent {
            amount,
            withdrawn_to: recipient,
            withdrawn_by: signer::address_of(admin),
            timestamp: timestamp::now_seconds(),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  EMERGENCY CONTROLS
    // ═══════════════════════════════════════════════════════════

    /// Pause platform (admin only)
    public entry fun pause_platform(
        admin: &signer,
        reason: String,
    ) acquires PlatformConfig {
        assert_is_admin(admin);
        
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        config.is_paused = true;
        config.paused_at = timestamp::now_seconds();
        config.paused_reason = reason;
        
        event::emit_event(&mut config.platform_paused_events, PlatformPausedEvent {
            reason,
            paused_by: signer::address_of(admin),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Unpause platform (admin only)
    public entry fun unpause_platform(
        admin: &signer,
    ) acquires PlatformConfig {
        assert_is_admin(admin);
        
        let config = borrow_global_mut<PlatformConfig>(@campus_cuts);
        config.is_paused = false;
        config.paused_at = 0;
        config.paused_reason = std::string::utf8(b"");
        
        event::emit_event(&mut config.platform_unpaused_events, PlatformUnpausedEvent {
            unpaused_by: signer::address_of(admin),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Assert platform is not paused
    public fun assert_not_paused() acquires PlatformConfig {
        let config = borrow_global<PlatformConfig>(@campus_cuts);
        assert!(!config.is_paused, E_PLATFORM_PAUSED);
    }

    // ═══════════════════════════════════════════════════════════
    //  HELPER FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    /// Check if caller is admin
    fun assert_is_admin(caller: &signer) acquires PlatformConfig {
        let config = borrow_global<PlatformConfig>(@campus_cuts);
        let caller_addr = signer::address_of(caller);
        
        let is_admin = caller_addr == config.root_admin || 
                      vector::contains(&config.admins, &caller_addr);
        
        assert!(is_admin, E_NOT_AUTHORIZED);
    }

    // ═══════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    #[view]
    public fun is_admin(addr: address): bool acquires PlatformConfig {
        let config = borrow_global<PlatformConfig>(@campus_cuts);
        addr == config.root_admin || vector::contains(&config.admins, &addr)
    }

    #[view]
    public fun is_paused(): bool acquires PlatformConfig {
        borrow_global<PlatformConfig>(@campus_cuts).is_paused
    }

    #[view]
    public fun get_accumulated_fees(): u64 acquires PlatformConfig {
        borrow_global<PlatformConfig>(@campus_cuts).accumulated_fees
    }

    #[view]
    public fun get_platform_stats(): (u64, u64, u64) acquires PlatformConfig {
        let config = borrow_global<PlatformConfig>(@campus_cuts);
        (
            config.total_disputes_handled,
            config.total_refunds_issued,
            config.total_bookings_created
        )
    }

    #[view]
    public fun get_open_disputes_count(): u64 acquires DisputeRegistry {
        vector::length(&borrow_global<DisputeRegistry>(@campus_cuts).open_disputes)
    }
}

