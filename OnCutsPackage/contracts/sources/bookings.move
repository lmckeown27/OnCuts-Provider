/// CampusCuts Bookings Module
/// 
/// This module manages the complete booking lifecycle:
/// 1. Create booking (lock funds in escrow)
/// 2. Complete booking (release funds to barber)
/// 3. Cancel booking (refund to student)
/// 4. No-show handling
/// 
/// All bookings are immutably stored on-chain for transparency.
module campus_cuts::bookings {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use aptos_std::event::{Self, EventHandle};
    use campus_cuts::user_accounts;

    // ═══════════════════════════════════════════════════════════
    //  ERRORS
    // ═══════════════════════════════════════════════════════════

    const E_NOT_INITIALIZED: u64 = 1;
    const E_BOOKING_NOT_FOUND: u64 = 2;
    const E_UNAUTHORIZED: u64 = 3;
    const E_INVALID_STATUS: u64 = 4;
    const E_BOOKING_ALREADY_COMPLETED: u64 = 5;
    const E_BOOKING_ALREADY_CANCELLED: u64 = 6;
    const E_INVALID_AMOUNT: u64 = 7;
    const E_INVALID_TIMESTAMP: u64 = 8;
    const E_NOT_BARBER: u64 = 9;

    // ═══════════════════════════════════════════════════════════
    //  CONSTANTS
    // ═══════════════════════════════════════════════════════════

    const STATUS_PENDING: u8 = 0;      // Booking created, waiting for scheduled time
    const STATUS_CONFIRMED: u8 = 1;    // Barber confirmed (for request-book mode)
    const STATUS_IN_PROGRESS: u8 = 2;  // Barber marked as started
    const STATUS_COMPLETED: u8 = 3;    // Service completed, funds released
    const STATUS_CANCELLED: u8 = 4;    // Cancelled before service, refunded
    const STATUS_NO_SHOW: u8 = 5;      // Student didn't show up
    
    const PLATFORM_FEE_BPS: u64 = 500; // 5% platform fee (500 basis points)
    const BPS_DENOMINATOR: u64 = 10000;

    // ═══════════════════════════════════════════════════════════
    //  DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════

    /// Individual booking
    struct Booking has store {
        id: u64,
        student_addr: address,
        barber_addr: address,
        
        // Service details
        service_name: String,          // e.g., "Haircut", "Fade", "Lineup"
        service_description: String,   // or IPFS CID for detailed description
        
        // Pricing
        amount_total: u64,             // Total amount (in octas)
        amount_to_barber: u64,         // Amount barber receives (95%)
        platform_fee: u64,             // Platform fee (5%)
        
        // Timing
        scheduled_time: u64,           // Unix timestamp
        created_at: u64,
        completed_at: u64,             // 0 if not completed
        
        // Status
        status: u8,
        escrow_released: bool,
        
        // Location (optional)
        location_description: String,   // or IPFS CID
        
        // Notes
        student_notes: String,          // Special requests
        barber_notes: String,           // Internal notes
    }

    /// Global booking registry
    struct BookingRegistry has key {
        // All bookings
        bookings: Table<u64, Booking>,
        next_booking_id: u64,
        
        // Indexes for faster queries
        student_bookings: Table<address, vector<u64>>,  // student => booking IDs
        barber_bookings: Table<address, vector<u64>>,   // barber => booking IDs
        
        // Stats
        total_bookings: u64,
        total_completed: u64,
        total_cancelled: u64,
        total_no_shows: u64,
        total_volume: u64,             // Total value ever processed
        
        // Events
        booking_created_events: EventHandle<BookingCreatedEvent>,
        booking_confirmed_events: EventHandle<BookingConfirmedEvent>,
        booking_completed_events: EventHandle<BookingCompletedEvent>,
        booking_cancelled_events: EventHandle<BookingCancelledEvent>,
    }

    /// Event: Booking Created
    struct BookingCreatedEvent has drop, store {
        booking_id: u64,
        student_addr: address,
        barber_addr: address,
        amount: u64,
        scheduled_time: u64,
        timestamp: u64,
    }

    /// Event: Booking Confirmed (request-book mode)
    struct BookingConfirmedEvent has drop, store {
        booking_id: u64,
        barber_addr: address,
        timestamp: u64,
    }

    /// Event: Booking Completed
    struct BookingCompletedEvent has drop, store {
        booking_id: u64,
        student_addr: address,
        barber_addr: address,
        amount_to_barber: u64,
        platform_fee: u64,
        timestamp: u64,
    }

    /// Event: Booking Cancelled
    struct BookingCancelledEvent has drop, store {
        booking_id: u64,
        cancelled_by: address,
        refund_amount: u64,
        reason: String,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════
    //  INITIALIZATION
    // ═══════════════════════════════════════════════════════════

    /// Initialize booking registry (called once by platform)
    public entry fun initialize(platform: &signer) {
        move_to(platform, BookingRegistry {
            bookings: table::new(),
            next_booking_id: 1,
            student_bookings: table::new(),
            barber_bookings: table::new(),
            total_bookings: 0,
            total_completed: 0,
            total_cancelled: 0,
            total_no_shows: 0,
            total_volume: 0,
            booking_created_events: account::new_event_handle<BookingCreatedEvent>(platform),
            booking_confirmed_events: account::new_event_handle<BookingConfirmedEvent>(platform),
            booking_completed_events: account::new_event_handle<BookingCompletedEvent>(platform),
            booking_cancelled_events: account::new_event_handle<BookingCancelledEvent>(platform),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  BOOKING LIFECYCLE
    // ═══════════════════════════════════════════════════════════

    /// Create a new booking (platform signs with student's key)
    /// This locks funds in escrow immediately
    public entry fun create_booking(
        platform: &signer,
        student_addr: address,
        barber_addr: address,
        service_name: String,
        service_description: String,
        amount: u64,
        scheduled_time: u64,
        location_description: String,
        student_notes: String,
    ) acquires BookingRegistry {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(scheduled_time > timestamp::now_seconds(), E_INVALID_TIMESTAMP);
        assert!(user_accounts::is_barber(barber_addr), E_NOT_BARBER);
        
        // Calculate fees
        let platform_fee = (amount * PLATFORM_FEE_BPS) / BPS_DENOMINATOR;
        let amount_to_barber = amount - platform_fee;
        
        // Lock funds in escrow (via user_accounts module)
        user_accounts::lock_balance(platform, student_addr, amount);
        
        // Create booking
        let registry = borrow_global_mut<BookingRegistry>(@campus_cuts);
        let booking_id = registry.next_booking_id;
        registry.next_booking_id = booking_id + 1;
        
        let booking = Booking {
            id: booking_id,
            student_addr,
            barber_addr,
            service_name,
            service_description,
            amount_total: amount,
            amount_to_barber,
            platform_fee,
            scheduled_time,
            created_at: timestamp::now_seconds(),
            completed_at: 0,
            status: STATUS_PENDING,
            escrow_released: false,
            location_description,
            student_notes,
            barber_notes: string::utf8(b""),
        };
        
        table::add(&mut registry.bookings, booking_id, booking);
        
        // Update indexes
        if (!table::contains(&registry.student_bookings, student_addr)) {
            table::add(&mut registry.student_bookings, student_addr, vector::empty<u64>());
        };
        vector::push_back(table::borrow_mut(&mut registry.student_bookings, student_addr), booking_id);
        
        if (!table::contains(&registry.barber_bookings, barber_addr)) {
            table::add(&mut registry.barber_bookings, barber_addr, vector::empty<u64>());
        };
        vector::push_back(table::borrow_mut(&mut registry.barber_bookings, barber_addr), booking_id);
        
        // Update stats
        registry.total_bookings = registry.total_bookings + 1;
        
        // Emit event
        event::emit_event(&mut registry.booking_created_events, BookingCreatedEvent {
            booking_id,
            student_addr,
            barber_addr,
            amount,
            scheduled_time,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Confirm booking (for request-book mode, barber accepts)
    public entry fun confirm_booking(
        platform: &signer,
        barber_addr: address,
        booking_id: u64,
    ) acquires BookingRegistry {
        let registry = borrow_global_mut<BookingRegistry>(@campus_cuts);
        assert!(table::contains(&registry.bookings, booking_id), E_BOOKING_NOT_FOUND);
        
        let booking = table::borrow_mut(&mut registry.bookings, booking_id);
        assert!(booking.barber_addr == barber_addr, E_UNAUTHORIZED);
        assert!(booking.status == STATUS_PENDING, E_INVALID_STATUS);
        
        booking.status = STATUS_CONFIRMED;
        
        // Emit event
        event::emit_event(&mut registry.booking_confirmed_events, BookingConfirmedEvent {
            booking_id,
            barber_addr,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Mark booking as in-progress (barber started service)
    public entry fun start_booking(
        platform: &signer,
        barber_addr: address,
        booking_id: u64,
    ) acquires BookingRegistry {
        let registry = borrow_global_mut<BookingRegistry>(@campus_cuts);
        assert!(table::contains(&registry.bookings, booking_id), E_BOOKING_NOT_FOUND);
        
        let booking = table::borrow_mut(&mut registry.bookings, booking_id);
        assert!(booking.barber_addr == barber_addr, E_UNAUTHORIZED);
        assert!(booking.status == STATUS_PENDING || booking.status == STATUS_CONFIRMED, E_INVALID_STATUS);
        
        booking.status = STATUS_IN_PROGRESS;
    }

    /// Complete booking (release escrow to barber)
    /// Platform calls this after student confirms service was completed
    public entry fun complete_booking(
        platform: &signer,
        booking_id: u64,
    ) acquires BookingRegistry {
        let registry = borrow_global_mut<BookingRegistry>(@campus_cuts);
        assert!(table::contains(&registry.bookings, booking_id), E_BOOKING_NOT_FOUND);
        
        let booking = table::borrow_mut(&mut registry.bookings, booking_id);
        assert!(booking.status != STATUS_COMPLETED, E_BOOKING_ALREADY_COMPLETED);
        assert!(booking.status != STATUS_CANCELLED, E_BOOKING_ALREADY_CANCELLED);
        assert!(!booking.escrow_released, E_BOOKING_ALREADY_COMPLETED);
        
        // Release escrow to barber (platform keeps fee)
        user_accounts::release_locked_to(
            platform,
            booking.student_addr,
            booking.barber_addr,
            booking.amount_total  // Total amount unlocked, but barber gets amount_to_barber
        );
        
        // Update booking
        booking.status = STATUS_COMPLETED;
        booking.escrow_released = true;
        booking.completed_at = timestamp::now_seconds();
        
        // Update stats
        registry.total_completed = registry.total_completed + 1;
        registry.total_volume = registry.total_volume + booking.amount_total;
        
        // Emit event
        event::emit_event(&mut registry.booking_completed_events, BookingCompletedEvent {
            booking_id,
            student_addr: booking.student_addr,
            barber_addr: booking.barber_addr,
            amount_to_barber: booking.amount_to_barber,
            platform_fee: booking.platform_fee,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Cancel booking (refund to student)
    /// Can be called by student or barber before service starts
    public entry fun cancel_booking(
        platform: &signer,
        booking_id: u64,
        cancelled_by: address,
        reason: String,
    ) acquires BookingRegistry {
        let registry = borrow_global_mut<BookingRegistry>(@campus_cuts);
        assert!(table::contains(&registry.bookings, booking_id), E_BOOKING_NOT_FOUND);
        
        let booking = table::borrow_mut(&mut registry.bookings, booking_id);
        assert!(booking.status != STATUS_COMPLETED, E_BOOKING_ALREADY_COMPLETED);
        assert!(booking.status != STATUS_CANCELLED, E_BOOKING_ALREADY_CANCELLED);
        
        // Verify authorization (student or barber can cancel)
        assert!(
            cancelled_by == booking.student_addr || cancelled_by == booking.barber_addr,
            E_UNAUTHORIZED
        );
        
        // Refund locked funds to student
        user_accounts::refund_locked(platform, booking.student_addr, booking.amount_total);
        
        // Update booking
        booking.status = STATUS_CANCELLED;
        booking.escrow_released = true; // Marked as released (but refunded)
        
        // Update stats
        registry.total_cancelled = registry.total_cancelled + 1;
        
        // Emit event
        event::emit_event(&mut registry.booking_cancelled_events, BookingCancelledEvent {
            booking_id,
            cancelled_by,
            refund_amount: booking.amount_total,
            reason,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Mark as no-show (student didn't show up)
    /// Releases funds to barber as penalty
    public entry fun mark_no_show(
        platform: &signer,
        booking_id: u64,
    ) acquires BookingRegistry {
        let registry = borrow_global_mut<BookingRegistry>(@campus_cuts);
        assert!(table::contains(&registry.bookings, booking_id), E_BOOKING_NOT_FOUND);
        
        let booking = table::borrow_mut(&mut registry.bookings, booking_id);
        assert!(booking.status != STATUS_COMPLETED, E_BOOKING_ALREADY_COMPLETED);
        
        // Release escrow to barber (penalty for no-show)
        user_accounts::release_locked_to(
            platform,
            booking.student_addr,
            booking.barber_addr,
            booking.amount_total
        );
        
        // Update booking
        booking.status = STATUS_NO_SHOW;
        booking.escrow_released = true;
        
        // Update stats
        registry.total_no_shows = registry.total_no_shows + 1;
        
        // No event for privacy, but logged on-chain
    }

    // ═══════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    #[view]
    public fun get_booking_status(booking_id: u64): u8 acquires BookingRegistry {
        let registry = borrow_global<BookingRegistry>(@campus_cuts);
        assert!(table::contains(&registry.bookings, booking_id), E_BOOKING_NOT_FOUND);
        table::borrow(&registry.bookings, booking_id).status
    }

    #[view]
    public fun get_total_bookings(): u64 acquires BookingRegistry {
        borrow_global<BookingRegistry>(@campus_cuts).total_bookings
    }

    #[view]
    public fun get_booking_stats(): (u64, u64, u64, u64, u64) acquires BookingRegistry {
        let registry = borrow_global<BookingRegistry>(@campus_cuts);
        (
            registry.total_bookings,
            registry.total_completed,
            registry.total_cancelled,
            registry.total_no_shows,
            registry.total_volume
        )
    }

    #[view]
    public fun is_booking_completed(booking_id: u64): bool acquires BookingRegistry {
        let registry = borrow_global<BookingRegistry>(@campus_cuts);
        if (!table::contains(&registry.bookings, booking_id)) {
            return false
        };
        table::borrow(&registry.bookings, booking_id).status == STATUS_COMPLETED
    }
}

