module campus_cuts::barber_registry {
    use std::signer;
    use std::string::String;
    use std::vector;
    use aptos_framework::timestamp;
    use aptos_framework::event::{Self, EventHandle};
    use aptos_framework::account;

    /// Error codes
    const E_NOT_AUTHORIZED: u64 = 1;
    const E_BARBER_NOT_FOUND: u64 = 2;
    const E_BARBER_ALREADY_EXISTS: u64 = 3;
    const E_INVALID_CAMPUS: u64 = 4;

    /// Barber profile stored on-chain
    struct BarberProfile has store, drop, copy {
        barber_address: address,
        campus_id: u64,
        specialties: vector<String>, // e.g., "Fades", "Braids", "Locs"
        is_active: bool,
        instant_book_enabled: bool,
        total_bookings: u64,
        joined_at: u64,
        bio_hash: vector<u8>, // Hash of bio stored off-chain
        pricing_hash: vector<u8>, // Hash of pricing structure
    }

    /// Service offering
    struct Service has store, drop, copy {
        barber_address: address,
        name: String,
        price: u64, // Price in cents
        duration_minutes: u64,
        is_available: bool,
    }

    /// Global barber registry
    struct BarberRegistry has key {
        barbers: vector<BarberProfile>,
        services: vector<Service>,
        barber_registered_events: EventHandle<BarberRegisteredEvent>,
        barber_updated_events: EventHandle<BarberUpdatedEvent>,
        service_added_events: EventHandle<ServiceAddedEvent>,
    }

    /// Events
    struct BarberRegisteredEvent has drop, store {
        barber_address: address,
        campus_id: u64,
        timestamp: u64,
    }

    struct BarberUpdatedEvent has drop, store {
        barber_address: address,
        timestamp: u64,
    }

    struct ServiceAddedEvent has drop, store {
        barber_address: address,
        service_name: String,
        price: u64,
    }

    /// Initialize barber registry
    public entry fun initialize(platform: &signer) {
        let platform_addr = signer::address_of(platform);
        
        if (!exists<BarberRegistry>(platform_addr)) {
            move_to(platform, BarberRegistry {
                barbers: vector::empty<BarberProfile>(),
                services: vector::empty<Service>(),
                barber_registered_events: account::new_event_handle<BarberRegisteredEvent>(platform),
                barber_updated_events: account::new_event_handle<BarberUpdatedEvent>(platform),
                service_added_events: account::new_event_handle<ServiceAddedEvent>(platform),
            });
        };
    }

    /// Register a new barber
    public entry fun register_barber(
        platform: &signer,
        barber_address: address,
        campus_id: u64,
        specialties: vector<String>,
        instant_book_enabled: bool,
        bio_hash: vector<u8>,
        pricing_hash: vector<u8>,
    ) acquires BarberRegistry {
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<BarberRegistry>(platform_addr);

        // Check if barber already exists
        assert!(!barber_exists(&registry.barbers, barber_address), E_BARBER_ALREADY_EXISTS);

        let profile = BarberProfile {
            barber_address,
            campus_id,
            specialties,
            is_active: true,
            instant_book_enabled,
            total_bookings: 0,
            joined_at: timestamp::now_seconds(),
            bio_hash,
            pricing_hash,
        };

        vector::push_back(&mut registry.barbers, profile);

        event::emit_event(&mut registry.barber_registered_events, BarberRegisteredEvent {
            barber_address,
            campus_id,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Add a service offering
    public entry fun add_service(
        platform: &signer,
        barber_address: address,
        name: String,
        price: u64,
        duration_minutes: u64,
    ) acquires BarberRegistry {
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<BarberRegistry>(platform_addr);

        // Verify barber exists
        assert!(barber_exists(&registry.barbers, barber_address), E_BARBER_NOT_FOUND);

        let service = Service {
            barber_address,
            name,
            price,
            duration_minutes,
            is_available: true,
        };

        vector::push_back(&mut registry.services, service);

        event::emit_event(&mut registry.service_added_events, ServiceAddedEvent {
            barber_address,
            service_name: name,
            price,
        });
    }

    /// Update barber profile
    public entry fun update_barber_profile(
        platform: &signer,
        barber_address: address,
        specialties: vector<String>,
        instant_book_enabled: bool,
        is_active: bool,
        bio_hash: vector<u8>,
        pricing_hash: vector<u8>,
    ) acquires BarberRegistry {
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<BarberRegistry>(platform_addr);

        let barber = find_barber_mut(&mut registry.barbers, barber_address);
        barber.specialties = specialties;
        barber.instant_book_enabled = instant_book_enabled;
        barber.is_active = is_active;
        barber.bio_hash = bio_hash;
        barber.pricing_hash = pricing_hash;

        event::emit_event(&mut registry.barber_updated_events, BarberUpdatedEvent {
            barber_address,
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Increment barber's total bookings (called by booking system)
    public entry fun increment_booking_count(
        platform: &signer,
        barber_address: address,
    ) acquires BarberRegistry {
        let platform_addr = signer::address_of(platform);
        let registry = borrow_global_mut<BarberRegistry>(platform_addr);

        let barber = find_barber_mut(&mut registry.barbers, barber_address);
        barber.total_bookings = barber.total_bookings + 1;
    }

    /// Get barber profile
    public fun get_barber_profile(
        platform_addr: address,
        barber_address: address
    ): BarberProfile acquires BarberRegistry {
        let registry = borrow_global<BarberRegistry>(platform_addr);
        *find_barber(&registry.barbers, barber_address)
    }

    /// Get all barbers for a campus
    public fun get_campus_barbers(
        platform_addr: address,
        campus_id: u64
    ): vector<BarberProfile> acquires BarberRegistry {
        let registry = borrow_global<BarberRegistry>(platform_addr);
        let campus_barbers = vector::empty<BarberProfile>();
        let len = vector::length(&registry.barbers);
        let i = 0;

        while (i < len) {
            let barber = vector::borrow(&registry.barbers, i);
            if (barber.campus_id == campus_id && barber.is_active) {
                vector::push_back(&mut campus_barbers, *barber);
            };
            i = i + 1;
        };

        campus_barbers
    }

    /// Get services offered by a barber
    public fun get_barber_services(
        platform_addr: address,
        barber_address: address
    ): vector<Service> acquires BarberRegistry {
        let registry = borrow_global<BarberRegistry>(platform_addr);
        let barber_services = vector::empty<Service>();
        let len = vector::length(&registry.services);
        let i = 0;

        while (i < len) {
            let service = vector::borrow(&registry.services, i);
            if (service.barber_address == barber_address && service.is_available) {
                vector::push_back(&mut barber_services, *service);
            };
            i = i + 1;
        };

        barber_services
    }

    /// Helper: Check if barber exists
    fun barber_exists(barbers: &vector<BarberProfile>, barber_address: address): bool {
        let len = vector::length(barbers);
        let i = 0;

        while (i < len) {
            let barber = vector::borrow(barbers, i);
            if (barber.barber_address == barber_address) {
                return true
            };
            i = i + 1;
        };

        false
    }

    /// Helper: Find barber (immutable)
    fun find_barber(barbers: &vector<BarberProfile>, barber_address: address): &BarberProfile {
        let len = vector::length(barbers);
        let i = 0;

        while (i < len) {
            let barber = vector::borrow(barbers, i);
            if (barber.barber_address == barber_address) {
                return barber
            };
            i = i + 1;
        };

        abort E_BARBER_NOT_FOUND
    }

    /// Helper: Find barber (mutable)
    fun find_barber_mut(barbers: &mut vector<BarberProfile>, barber_address: address): &mut BarberProfile {
        let len = vector::length(barbers);
        let i = 0;

        while (i < len) {
            let barber = vector::borrow_mut(barbers, i);
            if (barber.barber_address == barber_address) {
                return barber
            };
            i = i + 1;
        };

        abort E_BARBER_NOT_FOUND
    }

    #[test_only]
    use std::string;

    #[test(platform = @campus_cuts, barber = @0x456)]
    public fun test_register_barber(platform: &signer, barber: &signer) acquires BarberRegistry {
        timestamp::set_time_has_started_for_testing(platform);
        initialize(platform);
        
        let platform_addr = signer::address_of(platform);
        let barber_addr = signer::address_of(barber);

        let specialties = vector::empty<String>();
        vector::push_back(&mut specialties, string::utf8(b"Fades"));
        vector::push_back(&mut specialties, string::utf8(b"Tapers"));

        register_barber(
            platform,
            barber_addr,
            1, // campus_id
            specialties,
            true, // instant_book
            vector::empty<u8>(),
            vector::empty<u8>(),
        );

        let profile = get_barber_profile(platform_addr, barber_addr);
        assert!(profile.barber_address == barber_addr, 0);
        assert!(profile.campus_id == 1, 1);
        assert!(profile.is_active == true, 2);
    }
}

