module campus_cuts::review_system {
    use std::signer;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_REVIEW_NOT_FOUND: u64 = 2;
    const E_ALREADY_REVIEWED: u64 = 3;
    const E_INVALID_RATING: u64 = 4;
    const E_BARBER_NOT_FOUND: u64 = 5;

    /// Review structure
    struct Review has store, drop, copy {
        id: u64,
        booking_id: u64,
        barber_address: address,
        client_address: address,
        rating: u8, // 1-5 stars
        review_text_hash: vector<u8>, // Hash of full review text (stored off-chain)
        timestamp: u64,
        campus_id: u64,
    }

    /// Barber rating aggregation
    struct BarberRating has store, drop, copy {
        barber_address: address,
        total_reviews: u64,
        total_rating_points: u64,
        average_rating: u64, // Multiplied by 100 for precision (e.g., 450 = 4.5 stars)
    }

    /// Global review registry
    struct ReviewRegistry has key {
        reviews: vector<Review>,
        barber_ratings: vector<BarberRating>,
        next_review_id: u64,
        review_submitted_events: EventHandle<ReviewSubmittedEvent>,
    }

    /// Events
    struct ReviewSubmittedEvent has drop, store {
        review_id: u64,
        booking_id: u64,
        barber_address: address,
        rating: u8,
        timestamp: u64,
    }

    /// Initialize review registry
    public entry fun initialize(platform: &signer) {
        let platform_addr = signer::address_of(platform);
        
        if (!exists<ReviewRegistry>(platform_addr)) {
            move_to(platform, ReviewRegistry {
                reviews: vector::empty<Review>(),
                barber_ratings: vector::empty<BarberRating>(),
                next_review_id: 0,
                review_submitted_events: account::new_event_handle<ReviewSubmittedEvent>(platform),
            });
        };
    }

    /// Submit a review for a completed booking
    public entry fun submit_review(
        platform: &signer,
        client_address: address,
        booking_id: u64,
        barber_address: address,
        rating: u8,
        review_text_hash: vector<u8>,
        campus_id: u64,
    ) acquires ReviewRegistry {
        // Validate rating
        assert!(rating >= 1 && rating <= 5, E_INVALID_RATING);
        
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<ReviewRegistry>(platform_addr);

        // Check if booking already reviewed
        assert!(!has_review_for_booking(&registry.reviews, booking_id), E_ALREADY_REVIEWED);

        let review_id = registry.next_review_id;
        registry.next_review_id = review_id + 1;

        let review = Review {
            id: review_id,
            booking_id,
            barber_address,
            client_address,
            rating,
            review_text_hash,
            timestamp: timestamp::now_seconds(),
            campus_id,
        };

        vector::push_back(&mut registry.reviews, review);

        // Update barber rating
        update_barber_rating(registry, barber_address, rating);

        // Emit event
        event::emit_event(&mut registry.review_submitted_events, ReviewSubmittedEvent {
            review_id,
            booking_id,
            barber_address,
            rating,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Get reviews for a specific barber
    public fun get_barber_reviews(
        platform_addr: address,
        barber_address: address
    ): vector<Review> acquires ReviewRegistry {
        let registry = borrow_global<ReviewRegistry>(platform_addr);
        let barber_reviews = vector::empty<Review>();
        let len = vector::length(&registry.reviews);
        let i = 0;

        while (i < len) {
            let review = vector::borrow(&registry.reviews, i);
            if (review.barber_address == barber_address) {
                vector::push_back(&mut barber_reviews, *review);
            };
            i = i + 1;
        };

        barber_reviews
    }

    /// Get barber's average rating
    public fun get_barber_rating(
        platform_addr: address,
        barber_address: address
    ): (u64, u64) acquires ReviewRegistry {
        let registry = borrow_global<ReviewRegistry>(platform_addr);
        let rating_opt = find_barber_rating(&registry.barber_ratings, barber_address);
        
        if (vector::is_empty(&rating_opt)) {
            return (0, 0) // (average_rating, total_reviews)
        };

        let rating = vector::borrow(&rating_opt, 0);
        (rating.average_rating, rating.total_reviews)
    }

    /// Check if a booking has been reviewed
    fun has_review_for_booking(reviews: &vector<Review>, booking_id: u64): bool {
        let len = vector::length(reviews);
        let i = 0;

        while (i < len) {
            let review = vector::borrow(reviews, i);
            if (review.booking_id == booking_id) {
                return true
            };
            i = i + 1;
        };

        false
    }

    /// Update barber's aggregate rating
    fun update_barber_rating(registry: &mut ReviewRegistry, barber_address: address, new_rating: u8) {
        let barber_ratings = &mut registry.barber_ratings;
        let len = vector::length(barber_ratings);
        let i = 0;
        let found = false;

        // Try to find existing rating
        while (i < len) {
            let rating = vector::borrow_mut(barber_ratings, i);
            if (rating.barber_address == barber_address) {
                rating.total_reviews = rating.total_reviews + 1;
                rating.total_rating_points = rating.total_rating_points + (new_rating as u64);
                rating.average_rating = (rating.total_rating_points * 100) / rating.total_reviews;
                found = true;
                break
            };
            i = i + 1;
        };

        // Create new rating if not found
        if (!found) {
            vector::push_back(barber_ratings, BarberRating {
                barber_address,
                total_reviews: 1,
                total_rating_points: (new_rating as u64),
                average_rating: (new_rating as u64) * 100,
            });
        };
    }

    /// Helper to find barber rating
    fun find_barber_rating(ratings: &vector<BarberRating>, barber_address: address): vector<BarberRating> {
        let result = vector::empty<BarberRating>();
        let len = vector::length(ratings);
        let i = 0;

        while (i < len) {
            let rating = vector::borrow(ratings, i);
            if (rating.barber_address == barber_address) {
                vector::push_back(&mut result, *rating);
                return result
            };
            i = i + 1;
        };

        result
    }

    #[test_only]
    use std::string;

    #[test(platform = @campus_cuts, barber = @0x456, client = @0x789)]
    public fun test_submit_review(platform: &signer, barber: &signer, client: &signer) acquires ReviewRegistry {
        timestamp::set_time_has_started_for_testing(platform);
        initialize(platform);
        
        let platform_addr = signer::address_of(platform);
        let barber_addr = signer::address_of(barber);
        let client_addr = signer::address_of(client);

        // Submit review
        submit_review(
            platform,
            client_addr,
            1, // booking_id
            barber_addr,
            5, // 5-star rating
            vector::empty<u8>(),
            1, // campus_id
        );

        // Verify rating
        let (avg_rating, total_reviews) = get_barber_rating(platform_addr, barber_addr);
        assert!(avg_rating == 500, 0); // 5.00 stars
        assert!(total_reviews == 1, 1);

        // Submit another review
        submit_review(
            platform,
            client_addr,
            2, // different booking_id
            barber_addr,
            4, // 4-star rating
            vector::empty<u8>(),
            1,
        );

        let (avg_rating, total_reviews) = get_barber_rating(platform_addr, barber_addr);
        assert!(avg_rating == 450, 2); // 4.50 stars
        assert!(total_reviews == 2, 3);
    }
}

