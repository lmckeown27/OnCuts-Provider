/// CampusCuts Reviews Module
/// 
/// This module manages on-chain reviews for completed bookings.
/// - Ratings (1-5 stars) stored on-chain
/// - Review text stored on IPFS (CID stored on-chain)
/// - Weighted scoring based on student performance
/// - Immutable after creation (no editing/deletion)
/// 
/// Reviews are linked to bookings for verifiability.
module campus_cuts::reviews {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use aptos_std::event::{Self, EventHandle};
    use campus_cuts::bookings;

    // ═══════════════════════════════════════════════════════════
    //  ERRORS
    // ═══════════════════════════════════════════════════════════

    const E_NOT_INITIALIZED: u64 = 1;
    const E_REVIEW_ALREADY_EXISTS: u64 = 2;
    const E_BOOKING_NOT_COMPLETED: u64 = 3;
    const E_INVALID_RATING: u64 = 4;
    const E_UNAUTHORIZED: u64 = 5;
    const E_REVIEW_NOT_FOUND: u64 = 6;

    // ═══════════════════════════════════════════════════════════
    //  CONSTANTS
    // ═══════════════════════════════════════════════════════════

    const MIN_RATING: u8 = 1;
    const MAX_RATING: u8 = 5;

    // ═══════════════════════════════════════════════════════════
    //  DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════

    /// Individual review
    struct Review has store {
        id: u64,
        booking_id: u64,              // Link to booking
        
        // Participants
        student_addr: address,
        barber_addr: address,
        
        // Review content
        rating: u8,                   // 1-5 stars
        review_text_cid: String,      // IPFS CID for review text
        
        // Weighting (from student grading system)
        student_performance_score: u64, // Student's reliability score (0-100)
        review_weight: u64,           // How much this review counts (0-100)
        weighted_rating: u64,         // rating * weight (for aggregation)
        
        // Metadata
        created_at: u64,
        is_verified: bool,            // Verified that service actually happened
    }

    /// Barber aggregate ratings
    struct BarberRatings has store {
        barber_addr: address,
        
        // Unweighted (traditional)
        total_reviews: u64,
        sum_ratings: u64,             // Sum of all raw ratings
        average_rating: u64,          // (sum_ratings / total_reviews) * 100 (2 decimals)
        
        // Weighted (fair, considers student quality)
        total_weighted_reviews: u64,  // Sum of all weights
        sum_weighted_ratings: u64,    // Sum of (rating * weight)
        weighted_average_rating: u64, // (sum_weighted / total_weighted) * 100
        
        // Distribution
        rating_5_count: u64,
        rating_4_count: u64,
        rating_3_count: u64,
        rating_2_count: u64,
        rating_1_count: u64,
        
        last_updated: u64,
    }

    /// Global review registry
    struct ReviewRegistry has key {
        // All reviews
        reviews: Table<u64, Review>,           // review_id => Review
        booking_reviews: Table<u64, u64>,      // booking_id => review_id (one review per booking)
        next_review_id: u64,
        
        // Barber ratings
        barber_ratings: Table<address, BarberRatings>,
        
        // Indexes
        barber_reviews: Table<address, vector<u64>>,  // barber => review IDs
        student_reviews: Table<address, vector<u64>>, // student => review IDs
        
        // Stats
        total_reviews: u64,
        total_5_stars: u64,
        total_4_stars: u64,
        total_3_stars: u64,
        total_2_stars: u64,
        total_1_stars: u64,
        
        // Events
        review_created_events: EventHandle<ReviewCreatedEvent>,
        rating_updated_events: EventHandle<RatingUpdatedEvent>,
    }

    /// Event: Review Created
    struct ReviewCreatedEvent has drop, store {
        review_id: u64,
        booking_id: u64,
        student_addr: address,
        barber_addr: address,
        rating: u8,
        review_text_cid: String,
        review_weight: u64,
        timestamp: u64,
    }

    /// Event: Barber Rating Updated
    struct RatingUpdatedEvent has drop, store {
        barber_addr: address,
        new_average: u64,
        new_weighted_average: u64,
        total_reviews: u64,
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════
    //  INITIALIZATION
    // ═══════════════════════════════════════════════════════════

    /// Initialize review registry (called once by platform)
    public entry fun initialize(platform: &signer) {
        move_to(platform, ReviewRegistry {
            reviews: table::new(),
            booking_reviews: table::new(),
            next_review_id: 1,
            barber_ratings: table::new(),
            barber_reviews: table::new(),
            student_reviews: table::new(),
            total_reviews: 0,
            total_5_stars: 0,
            total_4_stars: 0,
            total_3_stars: 0,
            total_2_stars: 0,
            total_1_stars: 0,
            review_created_events: account::new_event_handle<ReviewCreatedEvent>(platform),
            rating_updated_events: account::new_event_handle<RatingUpdatedEvent>(platform),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  REVIEW CREATION
    // ═══════════════════════════════════════════════════════════

    /// Create review (platform signs with student's key)
    /// Only allowed after booking is completed
    public entry fun create_review(
        platform: &signer,
        student_addr: address,
        barber_addr: address,
        booking_id: u64,
        rating: u8,
        review_text_cid: String,
        student_performance_score: u64, // From student grading system (0-100)
    ) acquires ReviewRegistry {
        // Validate inputs
        assert!(rating >= MIN_RATING && rating <= MAX_RATING, E_INVALID_RATING);
        assert!(bookings::is_booking_completed(booking_id), E_BOOKING_NOT_COMPLETED);
        
        let registry = borrow_global_mut<ReviewRegistry>(@campus_cuts);
        
        // Ensure no duplicate review for this booking
        assert!(!table::contains(&registry.booking_reviews, booking_id), E_REVIEW_ALREADY_EXISTS);
        
        // Calculate review weight based on student performance
        // VIP students (90-100): 120% weight
        // Excellent (80-89): 110% weight
        // Good (70-79): 100% weight
        // Average (50-69): 80% weight
        // Below Average (30-49): 50% weight
        // Poor (0-29): 0% weight (review ignored)
        let review_weight = if (student_performance_score >= 90) {
            120
        } else if (student_performance_score >= 80) {
            110
        } else if (student_performance_score >= 70) {
            100
        } else if (student_performance_score >= 50) {
            80
        } else if (student_performance_score >= 30) {
            50
        } else {
            0 // Poor students' reviews are ignored
        };
        
        let weighted_rating = (rating as u64) * review_weight;
        
        // Create review
        let review_id = registry.next_review_id;
        registry.next_review_id = review_id + 1;
        
        let review = Review {
            id: review_id,
            booking_id,
            student_addr,
            barber_addr,
            rating,
            review_text_cid,
            student_performance_score,
            review_weight,
            weighted_rating,
            created_at: timestamp::now_seconds(),
            is_verified: true, // Verified because linked to completed booking
        };
        
        table::add(&mut registry.reviews, review_id, review);
        table::add(&mut registry.booking_reviews, booking_id, review_id);
        
        // Update indexes
        if (!table::contains(&registry.barber_reviews, barber_addr)) {
            table::add(&mut registry.barber_reviews, barber_addr, vector::empty<u64>());
        };
        vector::push_back(table::borrow_mut(&mut registry.barber_reviews, barber_addr), review_id);
        
        if (!table::contains(&registry.student_reviews, student_addr)) {
            table::add(&mut registry.student_reviews, student_addr, vector::empty<u64>());
        };
        vector::push_back(table::borrow_mut(&mut registry.student_reviews, student_addr), review_id);
        
        // Update barber ratings
        update_barber_ratings(registry, barber_addr, rating, review_weight, weighted_rating);
        
        // Update global stats
        registry.total_reviews = registry.total_reviews + 1;
        if (rating == 5) { registry.total_5_stars = registry.total_5_stars + 1 }
        else if (rating == 4) { registry.total_4_stars = registry.total_4_stars + 1 }
        else if (rating == 3) { registry.total_3_stars = registry.total_3_stars + 1 }
        else if (rating == 2) { registry.total_2_stars = registry.total_2_stars + 1 }
        else if (rating == 1) { registry.total_1_stars = registry.total_1_stars + 1 };
        
        // Emit event
        event::emit_event(&mut registry.review_created_events, ReviewCreatedEvent {
            review_id,
            booking_id,
            student_addr,
            barber_addr,
            rating,
            review_text_cid,
            review_weight,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Internal: Update barber's aggregate ratings
    fun update_barber_ratings(
        registry: &mut ReviewRegistry,
        barber_addr: address,
        rating: u8,
        weight: u64,
        weighted_rating: u64,
    ) {
        // Initialize if first review
        if (!table::contains(&registry.barber_ratings, barber_addr)) {
            table::add(&mut registry.barber_ratings, barber_addr, BarberRatings {
                barber_addr,
                total_reviews: 0,
                sum_ratings: 0,
                average_rating: 0,
                total_weighted_reviews: 0,
                sum_weighted_ratings: 0,
                weighted_average_rating: 0,
                rating_5_count: 0,
                rating_4_count: 0,
                rating_3_count: 0,
                rating_2_count: 0,
                rating_1_count: 0,
                last_updated: timestamp::now_seconds(),
            });
        };
        
        let ratings = table::borrow_mut(&mut registry.barber_ratings, barber_addr);
        
        // Update unweighted average
        ratings.total_reviews = ratings.total_reviews + 1;
        ratings.sum_ratings = ratings.sum_ratings + (rating as u64);
        ratings.average_rating = (ratings.sum_ratings * 100) / ratings.total_reviews;
        
        // Update weighted average (only if weight > 0)
        if (weight > 0) {
            ratings.total_weighted_reviews = ratings.total_weighted_reviews + weight;
            ratings.sum_weighted_ratings = ratings.sum_weighted_ratings + weighted_rating;
            ratings.weighted_average_rating = (ratings.sum_weighted_ratings * 100) / ratings.total_weighted_reviews;
        };
        
        // Update distribution
        if (rating == 5) { ratings.rating_5_count = ratings.rating_5_count + 1 }
        else if (rating == 4) { ratings.rating_4_count = ratings.rating_4_count + 1 }
        else if (rating == 3) { ratings.rating_3_count = ratings.rating_3_count + 1 }
        else if (rating == 2) { ratings.rating_2_count = ratings.rating_2_count + 1 }
        else if (rating == 1) { ratings.rating_1_count = ratings.rating_1_count + 1 };
        
        ratings.last_updated = timestamp::now_seconds();
        
        // Emit rating updated event
        event::emit_event(&mut registry.rating_updated_events, RatingUpdatedEvent {
            barber_addr,
            new_average: ratings.average_rating,
            new_weighted_average: ratings.weighted_average_rating,
            total_reviews: ratings.total_reviews,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    #[view]
    public fun get_barber_average_rating(barber_addr: address): (u64, u64) acquires ReviewRegistry {
        let registry = borrow_global<ReviewRegistry>(@campus_cuts);
        if (!table::contains(&registry.barber_ratings, barber_addr)) {
            return (0, 0) // No reviews yet
        };
        let ratings = table::borrow(&registry.barber_ratings, barber_addr);
        (ratings.average_rating, ratings.weighted_average_rating)
    }

    #[view]
    public fun get_barber_total_reviews(barber_addr: address): u64 acquires ReviewRegistry {
        let registry = borrow_global<ReviewRegistry>(@campus_cuts);
        if (!table::contains(&registry.barber_ratings, barber_addr)) {
            return 0
        };
        table::borrow(&registry.barber_ratings, barber_addr).total_reviews
    }

    #[view]
    public fun get_barber_rating_distribution(barber_addr: address): (u64, u64, u64, u64, u64) acquires ReviewRegistry {
        let registry = borrow_global<ReviewRegistry>(@campus_cuts);
        if (!table::contains(&registry.barber_ratings, barber_addr)) {
            return (0, 0, 0, 0, 0)
        };
        let ratings = table::borrow(&registry.barber_ratings, barber_addr);
        (
            ratings.rating_5_count,
            ratings.rating_4_count,
            ratings.rating_3_count,
            ratings.rating_2_count,
            ratings.rating_1_count
        )
    }

    #[view]
    public fun has_reviewed_booking(booking_id: u64): bool acquires ReviewRegistry {
        let registry = borrow_global<ReviewRegistry>(@campus_cuts);
        table::contains(&registry.booking_reviews, booking_id)
    }

    #[view]
    public fun get_total_reviews(): u64 acquires ReviewRegistry {
        borrow_global<ReviewRegistry>(@campus_cuts).total_reviews
    }

    #[view]
    public fun get_platform_rating_distribution(): (u64, u64, u64, u64, u64) acquires ReviewRegistry {
        let registry = borrow_global<ReviewRegistry>(@campus_cuts);
        (
            registry.total_5_stars,
            registry.total_4_stars,
            registry.total_3_stars,
            registry.total_2_stars,
            registry.total_1_stars
        )
    }
}

