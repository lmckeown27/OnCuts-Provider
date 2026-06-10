module campus_cuts::booking_system {
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_BOOKING_NOT_FOUND: u64 = 2;
    const E_INVALID_STATUS: u64 = 3;
    const E_BOOKING_ALREADY_EXISTS: u64 = 4;
    const E_INVALID_PRICE: u64 = 5;
    const E_CANNOT_CANCEL: u64 = 6;

    /// Booking status constants
    const STATUS_PENDING: u8 = 0;
    const STATUS_CONFIRMED: u8 = 1;
    const STATUS_COMPLETED: u8 = 2;
    const STATUS_CANCELLED: u8 = 3;

    /// Represents a single booking
    struct Booking has store, drop, copy {
        id: u64,
        barber_address: address,
        client_address: address,
        service_type: String,
        price: u64, // Price in cents (USD)
        scheduled_time: u64, // Unix timestamp
        created_at: u64,
        status: u8,
        campus_id: u64,
        duration_minutes: u64,
        location_hash: vector<u8>, // Hash of location details stored off-chain
    }

    /// Global booking registry stored at platform address
    struct BookingRegistry has key {
        bookings: vector<Booking>,
        next_booking_id: u64,
        booking_created_events: EventHandle<BookingCreatedEvent>,
        booking_confirmed_events: EventHandle<BookingConfirmedEvent>,
        booking_completed_events: EventHandle<BookingCompletedEvent>,
        booking_cancelled_events: EventHandle<BookingCancelledEvent>,
    }

    /// User's personal booking history
    struct UserBookings has key {
        booking_ids: vector<u64>,
    }

    /// Events
    struct BookingCreatedEvent has drop, store {
        booking_id: u64,
        barber_address: address,
        client_address: address,
        scheduled_time: u64,
        price: u64,
    }

    struct BookingConfirmedEvent has drop, store {
        booking_id: u64,
        confirmed_at: u64,
    }

    struct BookingCompletedEvent has drop, store {
        booking_id: u64,
        completed_at: u64,
    }

    struct BookingCancelledEvent has drop, store {
        booking_id: u64,
        cancelled_by: address,
        cancelled_at: u64,
    }

    /// Initialize the booking registry (called once by platform)
    public entry fun initialize(platform: &signer) {
        let platform_addr = signer::address_of(platform);
        
        if (!exists<BookingRegistry>(platform_addr)) {
            move_to(platform, BookingRegistry {
                bookings: vector::empty<Booking>(),
                next_booking_id: 0,
                booking_created_events: account::new_event_handle<BookingCreatedEvent>(platform),
                booking_confirmed_events: account::new_event_handle<BookingConfirmedEvent>(platform),
                booking_completed_events: account::new_event_handle<BookingCompletedEvent>(platform),
                booking_cancelled_events: account::new_event_handle<BookingCancelledEvent>(platform),
            });
        };
    }

    /// Initialize user bookings tracker
    fun ensure_user_bookings(user: &signer) {
        let user_addr = signer::address_of(user);
        if (!exists<UserBookings>(user_addr)) {
            move_to(user, UserBookings {
                booking_ids: vector::empty<u64>(),
            });
        };
    }

    /// Create a new booking
    public entry fun create_booking(
        platform: &signer,
        client_address: address,
        barber_address: address,
        service_type: String,
        price: u64,
        scheduled_time: u64,
        campus_id: u64,
        duration_minutes: u64,
        location_hash: vector<u8>,
    ) acquires BookingRegistry {
        assert!(price > 0, E_INVALID_PRICE);
        
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<BookingRegistry>(platform_addr);
        
        let booking_id = registry.next_booking_id;
        registry.next_booking_id = booking_id + 1;

        let booking = Booking {
            id: booking_id,
            barber_address,
            client_address,
            service_type,
            price,
            scheduled_time,
            created_at: timestamp::now_seconds(),
            status: STATUS_PENDING,
            campus_id,
            duration_minutes,
            location_hash,
        };

        vector::push_back(&mut registry.bookings, booking);

        // Emit event
        event::emit_event(&mut registry.booking_created_events, BookingCreatedEvent {
            booking_id,
            barber_address,
            client_address,
            scheduled_time,
            price,
        });
    }

    /// Barber confirms a booking
    public entry fun confirm_booking(
        barber: &signer,
        platform_addr: address,
        booking_id: u64,
    ) acquires BookingRegistry {
        let barber_addr = signer::address_of(barber);
        let registry = borrow_global_mut<BookingRegistry>(platform_addr);
        
        let booking = find_booking_mut(&mut registry.bookings, booking_id);
        assert!(booking.barber_address == barber_addr, E_NOT_AUTHORIZED);
        assert!(booking.status == STATUS_PENDING, E_INVALID_STATUS);

        booking.status = STATUS_CONFIRMED;

        event::emit_event(&mut registry.booking_confirmed_events, BookingConfirmedEvent {
            booking_id,
            confirmed_at: timestamp::now_seconds(),
        });
    }

    /// Complete a booking (triggers payment release)
    public entry fun complete_booking(
        barber: &signer,
        platform_addr: address,
        booking_id: u64,
    ) acquires BookingRegistry {
        let barber_addr = signer::address_of(barber);
        let registry = borrow_global_mut<BookingRegistry>(platform_addr);
        
        let booking = find_booking_mut(&mut registry.bookings, booking_id);
        assert!(booking.barber_address == barber_addr, E_NOT_AUTHORIZED);
        assert!(booking.status == STATUS_CONFIRMED, E_INVALID_STATUS);

        booking.status = STATUS_COMPLETED;

        event::emit_event(&mut registry.booking_completed_events, BookingCompletedEvent {
            booking_id,
            completed_at: timestamp::now_seconds(),
        });
    }

    /// Cancel a booking
    public entry fun cancel_booking(
        user: &signer,
        platform_addr: address,
        booking_id: u64,
    ) acquires BookingRegistry {
        let user_addr = signer::address_of(user);
        let registry = borrow_global_mut<BookingRegistry>(platform_addr);
        
        let booking = find_booking_mut(&mut registry.bookings, booking_id);
        
        // Only client or barber can cancel
        assert!(
            booking.client_address == user_addr || booking.barber_address == user_addr,
            E_NOT_AUTHORIZED
        );
        
        // Can only cancel if not completed
        assert!(booking.status != STATUS_COMPLETED, E_CANNOT_CANCEL);

        booking.status = STATUS_CANCELLED;

        event::emit_event(&mut registry.booking_cancelled_events, BookingCancelledEvent {
            booking_id,
            cancelled_by: user_addr,
            cancelled_at: timestamp::now_seconds(),
        });
    }

    /// Get booking details
    public fun get_booking(
        platform_addr: address,
        booking_id: u64
    ): Booking acquires BookingRegistry {
        let registry = borrow_global<BookingRegistry>(platform_addr);
        *find_booking(&registry.bookings, booking_id)
    }

    /// Get all bookings for a user (as client or barber)
    public fun get_user_bookings(
        platform_addr: address,
        user_addr: address
    ): vector<Booking> acquires BookingRegistry {
        let registry = borrow_global<BookingRegistry>(platform_addr);
        let user_bookings = vector::empty<Booking>();
        let len = vector::length(&registry.bookings);
        let i = 0;

        while (i < len) {
            let booking = vector::borrow(&registry.bookings, i);
            if (booking.client_address == user_addr || booking.barber_address == user_addr) {
                vector::push_back(&mut user_bookings, *booking);
            };
            i = i + 1;
        };

        user_bookings
    }

    /// Helper: Find booking by ID (immutable)
    fun find_booking(bookings: &vector<Booking>, booking_id: u64): &Booking {
        let len = vector::length(bookings);
        let i = 0;
        
        while (i < len) {
            let booking = vector::borrow(bookings, i);
            if (booking.id == booking_id) {
                return booking
            };
            i = i + 1;
        };
        
        abort E_BOOKING_NOT_FOUND
    }

    /// Helper: Find booking by ID (mutable)
    fun find_booking_mut(bookings: &mut vector<Booking>, booking_id: u64): &mut Booking {
        let len = vector::length(bookings);
        let i = 0;
        
        while (i < len) {
            let booking = vector::borrow_mut(bookings, i);
            if (booking.id == booking_id) {
                return booking
            };
            i = i + 1;
        };
        
        abort E_BOOKING_NOT_FOUND
    }

    /// Get total bookings count
    public fun get_total_bookings(platform_addr: address): u64 acquires BookingRegistry {
        let registry = borrow_global<BookingRegistry>(platform_addr);
        vector::length(&registry.bookings)
    }

    #[test_only]
    use std::string;

    #[test(platform = @campus_cuts, barber = @0x456, client = @0x789)]
    public fun test_create_booking(platform: &signer, barber: &signer, client: &signer) acquires BookingRegistry {
        // Initialize timestamp for testing
        timestamp::set_time_has_started_for_testing(platform);
        
        // Initialize registry
        initialize(platform);
        
        let platform_addr = signer::address_of(platform);
        let barber_addr = signer::address_of(barber);
        let client_addr = signer::address_of(client);

        // Create a booking
        create_booking(
            platform,
            client_addr,
            barber_addr,
            string::utf8(b"Fade Haircut"),
            2500, // $25.00
            1700000000, // Future timestamp
            1, // Campus ID
            45, // 45 minutes
            vector::empty<u8>(),
        );

        // Verify booking was created
        let booking = get_booking(platform_addr, 0);
        assert!(booking.id == 0, 0);
        assert!(booking.price == 2500, 1);
        assert!(booking.status == STATUS_PENDING, 2);
    }

    #[test(platform = @campus_cuts, barber = @0x456, client = @0x789)]
    public fun test_confirm_and_complete_booking(
        platform: &signer,
        barber: &signer,
        client: &signer
    ) acquires BookingRegistry {
        timestamp::set_time_has_started_for_testing(platform);
        initialize(platform);
        
        let platform_addr = signer::address_of(platform);
        let barber_addr = signer::address_of(barber);
        let client_addr = signer::address_of(client);

        // Create booking
        create_booking(
            platform,
            client_addr,
            barber_addr,
            string::utf8(b"Fade Haircut"),
            2500,
            1700000000,
            1,
            45,
            vector::empty<u8>(),
        );

        // Barber confirms
        confirm_booking(barber, platform_addr, 0);
        let booking = get_booking(platform_addr, 0);
        assert!(booking.status == STATUS_CONFIRMED, 0);

        // Barber completes
        complete_booking(barber, platform_addr, 0);
        let booking = get_booking(platform_addr, 0);
        assert!(booking.status == STATUS_COMPLETED, 1);
    }
}

