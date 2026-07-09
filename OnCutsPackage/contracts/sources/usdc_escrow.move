/**
 * USDC Escrow System for CampusCuts
 * 
 * Architecture:
 * - All payments flow through USDC (stablecoin)
 * - Platform custodial wallet holds USDC
 * - Smart contract locks USDC in escrow until service completion
 * - Gas fees paid in APT by platform (separate from USDC amounts)
 * - Clean 1:1 USD ↔ USDC conversion (no volatility)
 * 
 * Flow:
 * 1. Consumer pays $25 USD via Stripe
 * 2. Backend converts $25 → 25 USDC via Circle API
 * 3. Platform transfers 25 USDC to this escrow contract
 * 4. Service happens (barber cuts hair)
 * 5. Contract releases: 23.75 USDC to barber, 1.25 USDC to platform
 * 6. Backend converts 23.75 USDC → $23.75 USD, pays out to barber
 * 
 * Gas: ALL transactions paid by platform's APT wallet
 */

module campus_cuts::usdc_escrow {
    use std::signer;
    use std::vector;
    use aptos_framework::coin::{Self, Coin};
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    /// USDC coin type (adjust this to match Aptos USDC deployment)
    /// For testnet/devnet, replace with actual USDC module address
    struct USDC {}

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_ESCROW_NOT_FOUND: u64 = 2;
    const E_INSUFFICIENT_BALANCE: u64 = 3;
    const E_ALREADY_RELEASED: u64 = 4;
    const E_INVALID_AMOUNT: u64 = 5;
    const E_ALREADY_INITIALIZED: u64 = 6;
    const E_NOT_INITIALIZED: u64 = 7;

    /// Escrow status
    const STATUS_ESCROWED: u8 = 0;
    const STATUS_RELEASED: u8 = 1;
    const STATUS_REFUNDED: u8 = 2;
    const STATUS_DISPUTED: u8 = 3;

    /// Platform fee percentage (5% = 500 basis points)
    const PLATFORM_FEE_BPS: u64 = 500;
    const BPS_DENOMINATOR: u64 = 10000;

    /// Escrow record (tracks USDC held for a booking)
    struct EscrowRecord has store, drop, copy {
        booking_id: vector<u8>,        // UUID of booking
        barber_address: address,
        consumer_address: address,
        amount_usdc: u64,              // Total USDC locked (6 decimals)
        barber_payout_usdc: u64,       // 95% of amount
        platform_fee_usdc: u64,        // 5% of amount
        status: u8,
        created_at: u64,
        released_at: u64,
        stripe_payment_id: vector<u8>, // Reference to Stripe payment
    }

    /// Global escrow registry (owned by platform)
    struct EscrowRegistry has key {
        escrows: vector<EscrowRecord>,
        escrow_vault: Coin<USDC>,     // Holds all USDC in escrow
        total_escrowed_usdc: u64,
        total_released_usdc: u64,
        total_platform_fees_usdc: u64,
        // Events
        escrow_created_events: EventHandle<EscrowCreatedEvent>,
        escrow_released_events: EventHandle<EscrowReleasedEvent>,
        escrow_refunded_events: EventHandle<EscrowRefundedEvent>,
    }

    /// Events
    struct EscrowCreatedEvent has drop, store {
        booking_id: vector<u8>,
        amount_usdc: u64,
        barber_address: address,
        consumer_address: address,
        timestamp: u64,
    }

    struct EscrowReleasedEvent has drop, store {
        booking_id: vector<u8>,
        barber_payout_usdc: u64,
        platform_fee_usdc: u64,
        barber_address: address,
        timestamp: u64,
    }

    struct EscrowRefundedEvent has drop, store {
        booking_id: vector<u8>,
        amount_usdc: u64,
        consumer_address: address,
        timestamp: u64,
    }

    /// Initialize escrow system (called once by platform)
    /// Gas paid by: Platform
    public entry fun initialize(platform: &signer) {
        let platform_addr = signer::address_of(platform);
        
        assert!(!exists<EscrowRegistry>(platform_addr), E_ALREADY_INITIALIZED);

        move_to(platform, EscrowRegistry {
            escrows: vector::empty<EscrowRecord>(),
            escrow_vault: coin::zero<USDC>(),
            total_escrowed_usdc: 0,
            total_released_usdc: 0,
            total_platform_fees_usdc: 0,
            escrow_created_events: account::new_event_handle<EscrowCreatedEvent>(platform),
            escrow_released_events: account::new_event_handle<EscrowReleasedEvent>(platform),
            escrow_refunded_events: account::new_event_handle<EscrowRefundedEvent>(platform),
        });
    }

    /// Create escrow - lock USDC for a booking
    /// Gas paid by: Platform
    /// USDC flow: Platform custodial wallet → Escrow vault
    public entry fun create_escrow(
        platform: &signer,
        booking_id: vector<u8>,
        amount_usdc: u64,              // e.g., 25_000000 (25.00 USDC, 6 decimals)
        barber_address: address,
        consumer_address: address,
        stripe_payment_id: vector<u8>,
    ) acquires EscrowRegistry {
        let platform_addr = signer::address_of(platform);
        assert!(exists<EscrowRegistry>(platform_addr), E_NOT_INITIALIZED);
        assert!(amount_usdc > 0, E_INVALID_AMOUNT);

        let registry = borrow_global_mut<EscrowRegistry>(platform_addr);

        // Calculate splits (5% platform fee)
        let platform_fee_usdc = (amount_usdc * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        let barber_payout_usdc = amount_usdc - platform_fee_usdc;

        // Withdraw USDC from platform's wallet and deposit into escrow vault
        let usdc_to_lock = coin::withdraw<USDC>(platform, amount_usdc);
        coin::merge(&mut registry.escrow_vault, usdc_to_lock);

        // Create escrow record
        let escrow = EscrowRecord {
            booking_id,
            barber_address,
            consumer_address,
            amount_usdc,
            barber_payout_usdc,
            platform_fee_usdc,
            status: STATUS_ESCROWED,
            created_at: timestamp::now_seconds(),
            released_at: 0,
            stripe_payment_id,
        };

        vector::push_back(&mut registry.escrows, escrow);
        registry.total_escrowed_usdc = registry.total_escrowed_usdc + amount_usdc;

        // Emit event
        event::emit_event(&mut registry.escrow_created_events, EscrowCreatedEvent {
            booking_id,
            amount_usdc,
            barber_address,
            consumer_address,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Release payment - send USDC to barber and platform
    /// Gas paid by: Platform
    /// USDC flow: Escrow vault → Barber wallet (95%) + Platform wallet (5%)
    public entry fun release_payment(
        platform: &signer,
        booking_id: vector<u8>,
    ) acquires EscrowRegistry {
        let platform_addr = signer::address_of(platform);
        assert!(exists<EscrowRegistry>(platform_addr), E_NOT_INITIALIZED);

        let registry = borrow_global_mut<EscrowRegistry>(platform_addr);
        let escrow = find_escrow_mut(&mut registry.escrows, &booking_id);
        
        assert!(escrow.status == STATUS_ESCROWED, E_ALREADY_RELEASED);

        // Extract USDC from vault
        let barber_coins = coin::extract(&mut registry.escrow_vault, escrow.barber_payout_usdc);
        let platform_coins = coin::extract(&mut registry.escrow_vault, escrow.platform_fee_usdc);

        // Transfer to recipients
        // Note: Platform account must be registered for USDC
        coin::deposit(escrow.barber_address, barber_coins);
        coin::deposit(platform_addr, platform_coins);

        // Update escrow state
        escrow.status = STATUS_RELEASED;
        escrow.released_at = timestamp::now_seconds();

        // Update totals
        registry.total_released_usdc = registry.total_released_usdc + escrow.amount_usdc;
        registry.total_platform_fees_usdc = registry.total_platform_fees_usdc + escrow.platform_fee_usdc;

        // Emit event
        event::emit_event(&mut registry.escrow_released_events, EscrowReleasedEvent {
            booking_id,
            barber_payout_usdc: escrow.barber_payout_usdc,
            platform_fee_usdc: escrow.platform_fee_usdc,
            barber_address: escrow.barber_address,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Refund payment - return USDC to consumer
    /// Gas paid by: Platform
    /// USDC flow: Escrow vault → Consumer wallet (100%)
    public entry fun refund_payment(
        platform: &signer,
        booking_id: vector<u8>,
    ) acquires EscrowRegistry {
        let platform_addr = signer::address_of(platform);
        assert!(exists<EscrowRegistry>(platform_addr), E_NOT_INITIALIZED);

        let registry = borrow_global_mut<EscrowRegistry>(platform_addr);
        let escrow = find_escrow_mut(&mut registry.escrows, &booking_id);
        
        assert!(escrow.status == STATUS_ESCROWED, E_ALREADY_RELEASED);

        // Extract full amount from vault
        let refund_coins = coin::extract(&mut registry.escrow_vault, escrow.amount_usdc);

        // Transfer back to consumer
        coin::deposit(escrow.consumer_address, refund_coins);

        // Update escrow state
        escrow.status = STATUS_REFUNDED;
        escrow.released_at = timestamp::now_seconds();

        // Emit event
        event::emit_event(&mut registry.escrow_refunded_events, EscrowRefundedEvent {
            booking_id,
            amount_usdc: escrow.amount_usdc,
            consumer_address: escrow.consumer_address,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Get escrow details (view function)
    #[view]
    public fun get_escrow(
        platform_addr: address,
        booking_id: vector<u8>
    ): (u64, u64, u64, u8, address, address) acquires EscrowRegistry {
        let registry = borrow_global<EscrowRegistry>(platform_addr);
        let escrow = find_escrow(&registry.escrows, &booking_id);
        
        (
            escrow.amount_usdc,
            escrow.barber_payout_usdc,
            escrow.platform_fee_usdc,
            escrow.status,
            escrow.barber_address,
            escrow.consumer_address
        )
    }

    /// Get total USDC locked in escrow (view function)
    #[view]
    public fun get_total_escrowed(platform_addr: address): u64 acquires EscrowRegistry {
        let registry = borrow_global<EscrowRegistry>(platform_addr);
        coin::value(&registry.escrow_vault)
    }

    /// Get platform fee statistics (view function)
    #[view]
    public fun get_platform_stats(platform_addr: address): (u64, u64, u64) acquires EscrowRegistry {
        let registry = borrow_global<EscrowRegistry>(platform_addr);
        (
            registry.total_escrowed_usdc,
            registry.total_released_usdc,
            registry.total_platform_fees_usdc
        )
    }

    /// Helper: Find escrow (immutable)
    fun find_escrow(escrows: &vector<EscrowRecord>, booking_id: &vector<u8>): &EscrowRecord {
        let len = vector::length(escrows);
        let i = 0;

        while (i < len) {
            let escrow = vector::borrow(escrows, i);
            if (&escrow.booking_id == booking_id) {
                return escrow
            };
            i = i + 1;
        };

        abort E_ESCROW_NOT_FOUND
    }

    /// Helper: Find escrow (mutable)
    fun find_escrow_mut(escrows: &mut vector<EscrowRecord>, booking_id: &vector<u8>): &mut EscrowRecord {
        let len = vector::length(escrows);
        let i = 0;

        while (i < len) {
            let escrow = vector::borrow_mut(escrows, i);
            if (&escrow.booking_id == booking_id) {
                return escrow
            };
            i = i + 1;
        };

        abort E_ESCROW_NOT_FOUND
    }

    #[test_only]
    public fun init_for_test(platform: &signer) {
        initialize(platform);
    }

    #[test(platform = @campus_cuts, barber = @0x456, consumer = @0x789)]
    public fun test_escrow_flow(platform: &signer, barber: &signer, consumer: &signer) acquires EscrowRegistry {
        use std::vector;
        
        timestamp::set_time_has_started_for_testing(platform);
        initialize(platform);

        let platform_addr = signer::address_of(platform);
        let barber_addr = signer::address_of(barber);
        let consumer_addr = signer::address_of(consumer);

        // Register accounts for USDC (test setup)
        coin::register<USDC>(platform);
        coin::register<USDC>(barber);
        coin::register<USDC>(consumer);

        // Create mock booking ID
        let booking_id = b"test-booking-123";
        let amount = 25_000000; // 25.00 USDC

        // Fund platform with test USDC
        // (In real deployment, this would come from Circle API)
        let test_usdc = coin::withdraw<USDC>(platform, amount);
        coin::deposit(platform_addr, test_usdc);

        // Create escrow
        create_escrow(
            platform,
            booking_id,
            amount,
            barber_addr,
            consumer_addr,
            b"stripe_pi_test123",
        );

        // Verify escrow state
        let (escrowed_amount, barber_payout, platform_fee, status, _, _) = 
            get_escrow(platform_addr, booking_id);
        
        assert!(escrowed_amount == 25_000000, 1);
        assert!(barber_payout == 23_750000, 2);  // 95% of 25 USDC
        assert!(platform_fee == 1_250000, 3);     // 5% of 25 USDC
        assert!(status == STATUS_ESCROWED, 4);

        // Release payment
        release_payment(platform, booking_id);

        // Verify release
        let (_, _, _, new_status, _, _) = get_escrow(platform_addr, booking_id);
        assert!(new_status == STATUS_RELEASED, 5);

        // Verify balances
        let barber_balance = coin::balance<USDC>(barber_addr);
        let platform_balance = coin::balance<USDC>(platform_addr);
        
        assert!(barber_balance == 23_750000, 6);
        assert!(platform_balance == 1_250000, 7);
    }
}



