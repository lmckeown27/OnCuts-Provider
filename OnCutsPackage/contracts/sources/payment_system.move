module campus_cuts::payment_system {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_PAYMENT_NOT_FOUND: u64 = 2;
    const E_INSUFFICIENT_BALANCE: u64 = 3;
    const E_PAYMENT_ALREADY_RELEASED: u64 = 4;
    const E_INVALID_AMOUNT: u64 = 5;
    const E_BARBER_NOT_FOUND: u64 = 6;

    /// Payment status
    const STATUS_ESCROWED: u8 = 0;
    const STATUS_RELEASED: u8 = 1;
    const STATUS_REFUNDED: u8 = 2;

    /// Payment record (tracks fiat payments via hash)
    struct Payment has store, drop, copy {
        id: u64,
        booking_id: u64,
        barber_address: address,
        client_address: address,
        amount: u64, // Amount in cents (USD)
        platform_fee: u64, // 5% platform commission
        barber_payout: u64, // Amount after commission
        stripe_payment_id_hash: vector<u8>, // Hash of Stripe payment ID
        status: u8,
        created_at: u64,
        released_at: u64,
    }

    /// Barber earnings tracker
    struct BarberEarnings has store, drop, copy {
        barber_address: address,
        total_earnings: u64, // Total lifetime earnings in cents
        total_bookings_completed: u64,
        pending_payout: u64,
        last_payout_at: u64,
    }

    /// Global payment registry
    struct PaymentRegistry has key {
        payments: vector<Payment>,
        barber_earnings: vector<BarberEarnings>,
        next_payment_id: u64,
        total_platform_revenue: u64,
        payment_created_events: EventHandle<PaymentCreatedEvent>,
        payment_released_events: EventHandle<PaymentReleasedEvent>,
        payment_refunded_events: EventHandle<PaymentRefundedEvent>,
        payout_processed_events: EventHandle<PayoutProcessedEvent>,
    }

    /// Events
    struct PaymentCreatedEvent has drop, store {
        payment_id: u64,
        booking_id: u64,
        amount: u64,
        barber_address: address,
    }

    struct PaymentReleasedEvent has drop, store {
        payment_id: u64,
        booking_id: u64,
        barber_payout: u64,
        timestamp: u64,
    }

    struct PaymentRefundedEvent has drop, store {
        payment_id: u64,
        booking_id: u64,
        amount: u64,
        timestamp: u64,
    }

    struct PayoutProcessedEvent has drop, store {
        barber_address: address,
        amount: u64,
        timestamp: u64,
    }

    /// Initialize payment system
    public entry fun initialize(platform: &signer) {
        let platform_addr = signer::address_of(platform);
        
        if (!exists<PaymentRegistry>(platform_addr)) {
            move_to(platform, PaymentRegistry {
                payments: vector::empty<Payment>(),
                barber_earnings: vector::empty<BarberEarnings>(),
                next_payment_id: 0,
                total_platform_revenue: 0,
                payment_created_events: account::new_event_handle<PaymentCreatedEvent>(platform),
                payment_released_events: account::new_event_handle<PaymentReleasedEvent>(platform),
                payment_refunded_events: account::new_event_handle<PaymentRefundedEvent>(platform),
                payout_processed_events: account::new_event_handle<PayoutProcessedEvent>(platform),
            });
        };
    }

    /// Create payment record (escrowed via Stripe)
    public entry fun create_payment(
        platform: &signer,
        booking_id: u64,
        barber_address: address,
        client_address: address,
        amount: u64,
        stripe_payment_id_hash: vector<u8>,
    ) acquires PaymentRegistry {
        assert!(amount > 0, E_INVALID_AMOUNT);
        
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<PaymentRegistry>(platform_addr);

        let payment_id = registry.next_payment_id;
        registry.next_payment_id = payment_id + 1;

        // Calculate 5% platform fee
        let platform_fee = (amount * 5) / 100;
        let barber_payout = amount - platform_fee;

        let payment = Payment {
            id: payment_id,
            booking_id,
            barber_address,
            client_address,
            amount,
            platform_fee,
            barber_payout,
            stripe_payment_id_hash,
            status: STATUS_ESCROWED,
            created_at: timestamp::now_seconds(),
            released_at: 0,
        };

        vector::push_back(&mut registry.payments, payment);

        event::emit_event(&mut registry.payment_created_events, PaymentCreatedEvent {
            payment_id,
            booking_id,
            amount,
            barber_address,
        });
    }

    /// Release payment to barber after booking completion
    public entry fun release_payment(
        platform: &signer,
        payment_id: u64,
    ) acquires PaymentRegistry {
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<PaymentRegistry>(platform_addr);

        let payment = find_payment_mut(&mut registry.payments, payment_id);
        assert!(payment.status == STATUS_ESCROWED, E_PAYMENT_ALREADY_RELEASED);

        payment.status = STATUS_RELEASED;
        payment.released_at = timestamp::now_seconds();

        // Update barber earnings
        update_barber_earnings(
            &mut registry.barber_earnings,
            payment.barber_address,
            payment.barber_payout,
        );

        // Update platform revenue
        registry.total_platform_revenue = registry.total_platform_revenue + payment.platform_fee;

        event::emit_event(&mut registry.payment_released_events, PaymentReleasedEvent {
            payment_id,
            booking_id: payment.booking_id,
            barber_payout: payment.barber_payout,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Refund payment (booking cancellation)
    public entry fun refund_payment(
        platform: &signer,
        payment_id: u64,
    ) acquires PaymentRegistry {
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<PaymentRegistry>(platform_addr);

        let payment = find_payment_mut(&mut registry.payments, payment_id);
        assert!(payment.status == STATUS_ESCROWED, E_PAYMENT_ALREADY_RELEASED);

        payment.status = STATUS_REFUNDED;
        payment.released_at = timestamp::now_seconds();

        event::emit_event(&mut registry.payment_refunded_events, PaymentRefundedEvent {
            payment_id,
            booking_id: payment.booking_id,
            amount: payment.amount,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Process payout to barber (clears pending balance)
    public entry fun process_payout(
        platform: &signer,
        barber_address: address,
    ) acquires PaymentRegistry {
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<PaymentRegistry>(platform_addr);

        let earnings = find_barber_earnings_mut(&mut registry.barber_earnings, barber_address);
        let payout_amount = earnings.pending_payout;

        earnings.pending_payout = 0;
        earnings.last_payout_at = timestamp::now_seconds();

        event::emit_event(&mut registry.payout_processed_events, PayoutProcessedEvent {
            barber_address,
            amount: payout_amount,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Get barber earnings summary
    public fun get_barber_earnings(
        platform_addr: address,
        barber_address: address
    ): (u64, u64, u64) acquires PaymentRegistry {
        let registry = borrow_global<PaymentRegistry>(platform_addr);
        let earnings_vec = find_barber_earnings_vec(&registry.barber_earnings, barber_address);
        
        if (vector::is_empty(&earnings_vec)) {
            return (0, 0, 0) // (total_earnings, pending_payout, total_bookings)
        };

        let earnings = vector::borrow(&earnings_vec, 0);
        (earnings.total_earnings, earnings.pending_payout, earnings.total_bookings_completed)
    }

    /// Get payment by ID
    public fun get_payment(
        platform_addr: address,
        payment_id: u64
    ): Payment acquires PaymentRegistry {
        let registry = borrow_global<PaymentRegistry>(platform_addr);
        *find_payment(&registry.payments, payment_id)
    }

    /// Helper: Update barber earnings
    fun update_barber_earnings(
        earnings: &mut vector<BarberEarnings>,
        barber_address: address,
        payout_amount: u64,
    ) {
        let len = vector::length(earnings);
        let i = 0;
        let found = false;

        while (i < len) {
            let earning = vector::borrow_mut(earnings, i);
            if (earning.barber_address == barber_address) {
                earning.total_earnings = earning.total_earnings + payout_amount;
                earning.pending_payout = earning.pending_payout + payout_amount;
                earning.total_bookings_completed = earning.total_bookings_completed + 1;
                found = true;
                break
            };
            i = i + 1;
        };

        if (!found) {
            vector::push_back(earnings, BarberEarnings {
                barber_address,
                total_earnings: payout_amount,
                total_bookings_completed: 1,
                pending_payout: payout_amount,
                last_payout_at: 0,
            });
        };
    }

    /// Helper: Find payment (immutable)
    fun find_payment(payments: &vector<Payment>, payment_id: u64): &Payment {
        let len = vector::length(payments);
        let i = 0;

        while (i < len) {
            let payment = vector::borrow(payments, i);
            if (payment.id == payment_id) {
                return payment
            };
            i = i + 1;
        };

        abort E_PAYMENT_NOT_FOUND
    }

    /// Helper: Find payment (mutable)
    fun find_payment_mut(payments: &mut vector<Payment>, payment_id: u64): &mut Payment {
        let len = vector::length(payments);
        let i = 0;

        while (i < len) {
            let payment = vector::borrow_mut(payments, i);
            if (payment.id == payment_id) {
                return payment
            };
            i = i + 1;
        };

        abort E_PAYMENT_NOT_FOUND
    }

    /// Helper: Find barber earnings (vector result for optional)
    fun find_barber_earnings_vec(
        earnings: &vector<BarberEarnings>,
        barber_address: address
    ): vector<BarberEarnings> {
        let result = vector::empty<BarberEarnings>();
        let len = vector::length(earnings);
        let i = 0;

        while (i < len) {
            let earning = vector::borrow(earnings, i);
            if (earning.barber_address == barber_address) {
                vector::push_back(&mut result, *earning);
                return result
            };
            i = i + 1;
        };

        result
    }

    /// Helper: Find barber earnings (mutable)
    fun find_barber_earnings_mut(
        earnings: &mut vector<BarberEarnings>,
        barber_address: address
    ): &mut BarberEarnings {
        let len = vector::length(earnings);
        let i = 0;

        while (i < len) {
            let earning = vector::borrow_mut(earnings, i);
            if (earning.barber_address == barber_address) {
                return earning
            };
            i = i + 1;
        };

        abort E_BARBER_NOT_FOUND
    }

    #[test(platform = @campus_cuts, barber = @0x456, client = @0x789)]
    public fun test_payment_flow(platform: &signer, barber: &signer, client: &signer) acquires PaymentRegistry {
        timestamp::set_time_has_started_for_testing(platform);
        initialize(platform);
        
        let platform_addr = signer::address_of(platform);
        let barber_addr = signer::address_of(barber);
        let client_addr = signer::address_of(client);

        // Create payment
        create_payment(
            platform,
            1, // booking_id
            barber_addr,
            client_addr,
            2500, // $25.00
            vector::empty<u8>(),
        );

        let payment = get_payment(platform_addr, 0);
        assert!(payment.amount == 2500, 0);
        assert!(payment.platform_fee == 125, 1); // 5% of 2500
        assert!(payment.barber_payout == 2375, 2); // 95% of 2500
        assert!(payment.status == STATUS_ESCROWED, 3);

        // Release payment
        release_payment(platform, 0);
        
        let payment = get_payment(platform_addr, 0);
        assert!(payment.status == STATUS_RELEASED, 4);

        // Check barber earnings
        let (total, pending, bookings) = get_barber_earnings(platform_addr, barber_addr);
        assert!(total == 2375, 5);
        assert!(pending == 2375, 6);
        assert!(bookings == 1, 7);
    }
}

