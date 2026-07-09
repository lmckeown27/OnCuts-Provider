/// CampusCuts User Accounts Module
/// 
/// This module manages all user accounts (students, barbers, admins) on-chain.
/// Each user has a balance, profile metadata, and campus affiliation.
/// 
/// **Custodial Model:** Platform derives addresses from emails and signs on behalf of users.
module campus_cuts::user_accounts {
    use std::signer;
    use std::string::{Self, String};
    use std::vector;
    use aptos_framework::account;
    use aptos_framework::coin;
    use aptos_framework::aptos_coin::AptosCoin;
    use aptos_framework::timestamp;
    use aptos_std::table::{Self, Table};
    use aptos_std::event::{Self, EventHandle};

    // ═══════════════════════════════════════════════════════════
    //  ERRORS
    // ═══════════════════════════════════════════════════════════

    const E_NOT_INITIALIZED: u64 = 1;
    const E_ALREADY_REGISTERED: u64 = 2;
    const E_NOT_REGISTERED: u64 = 3;
    const E_INSUFFICIENT_BALANCE: u64 = 4;
    const E_INVALID_AMOUNT: u64 = 5;
    const E_UNAUTHORIZED: u64 = 6;
    const E_ACCOUNT_SUSPENDED: u64 = 7;
    const E_INVALID_ROLE: u64 = 8;

    // ═══════════════════════════════════════════════════════════
    //  CONSTANTS
    // ═══════════════════════════════════════════════════════════

    const ROLE_STUDENT: u8 = 0;
    const ROLE_BARBER: u8 = 1;
    const ROLE_ADMIN: u8 = 2;

    // ═══════════════════════════════════════════════════════════
    //  DATA STRUCTURES
    // ═══════════════════════════════════════════════════════════

    /// Individual user account
    struct UserAccount has key {
        // Identity
        user_address: address,
        email_hash: vector<u8>,        // SHA256 hash of email (privacy)
        campus_domain: String,         // e.g., "calpoly.edu"
        role: u8,                      // 0=student, 1=barber, 2=admin
        
        // Balances (in octas - 1 APT = 100,000,000 octas)
        balance_available: u64,        // Spendable balance
        balance_locked: u64,           // In escrow for bookings
        
        // Profile (IPFS CIDs)
        profile_photo_cid: String,     // IPFS CID for profile picture
        bio: String,                   // Short bio (or IPFS CID if long)
        username: String,              // Display name
        phone_hash: vector<u8>,        // SHA256 hash of phone (privacy)
        
        // Metadata
        created_at: u64,               // Timestamp
        last_active: u64,              // Last interaction timestamp
        is_active: bool,               // Account status
        is_verified: bool,             // Email/ID verified
        
        // Barber-specific (only populated if role == ROLE_BARBER)
        years_of_experience: u8,
        specialties: vector<String>,   // e.g., ["Fades", "Lineups"]
        instant_book_enabled: bool,
        portfolio_cids: vector<String>, // IPFS CIDs for portfolio images
        
        // Stats
        total_bookings: u64,           // Lifetime bookings (as student or barber)
        total_spent: u64,              // Lifetime spending (students)
        total_earned: u64,             // Lifetime earnings (barbers)
    }

    /// Global registry of all users
    struct UserRegistry has key {
        // Map: address => UserAccount (reference only, actual data in UserAccount resource)
        users: Table<address, bool>,  // Just tracks existence
        
        // Counters
        total_students: u64,
        total_barbers: u64,
        total_admins: u64,
        
        // Events
        user_registered_events: EventHandle<UserRegisteredEvent>,
        balance_updated_events: EventHandle<BalanceUpdatedEvent>,
        profile_updated_events: EventHandle<ProfileUpdatedEvent>,
    }

    /// Event: User Registration
    struct UserRegisteredEvent has drop, store {
        user_address: address,
        campus_domain: String,
        role: u8,
        timestamp: u64,
    }

    /// Event: Balance Update
    struct BalanceUpdatedEvent has drop, store {
        user_address: address,
        available_before: u64,
        available_after: u64,
        locked_before: u64,
        locked_after: u64,
        reason: String, // "deposit", "booking", "refund", "withdrawal"
        timestamp: u64,
    }

    /// Event: Profile Update
    struct ProfileUpdatedEvent has drop, store {
        user_address: address,
        field: String, // "photo", "bio", "username"
        timestamp: u64,
    }

    // ═══════════════════════════════════════════════════════════
    //  INITIALIZATION
    // ═══════════════════════════════════════════════════════════

    /// Initialize the user registry (called once by platform)
    public entry fun initialize(platform: &signer) {
        let platform_addr = signer::address_of(platform);
        
        // Create global registry
        move_to(platform, UserRegistry {
            users: table::new(),
            total_students: 0,
            total_barbers: 0,
            total_admins: 0,
            user_registered_events: account::new_event_handle<UserRegisteredEvent>(platform),
            balance_updated_events: account::new_event_handle<BalanceUpdatedEvent>(platform),
            profile_updated_events: account::new_event_handle<ProfileUpdatedEvent>(platform),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  USER REGISTRATION
    // ═══════════════════════════════════════════════════════════

    /// Register a new user (called by platform on behalf of user)
    /// Platform signs this transaction with the user's derived account
    public entry fun register_user(
        user: &signer,
        email_hash: vector<u8>,
        campus_domain: String,
        role: u8,
        username: String,
    ) acquires UserRegistry {
        let user_addr = signer::address_of(user);
        
        // Validate role
        assert!(role <= ROLE_ADMIN, E_INVALID_ROLE);
        
        // Ensure not already registered
        assert!(!exists<UserAccount>(user_addr), E_ALREADY_REGISTERED);
        
        // Create user account
        move_to(user, UserAccount {
            user_address: user_addr,
            email_hash,
            campus_domain,
            role,
            balance_available: 0,
            balance_locked: 0,
            profile_photo_cid: string::utf8(b""),
            bio: string::utf8(b""),
            username,
            phone_hash: vector::empty(),
            created_at: timestamp::now_seconds(),
            last_active: timestamp::now_seconds(),
            is_active: true,
            is_verified: false,
            years_of_experience: 0,
            specialties: vector::empty(),
            instant_book_enabled: false,
            portfolio_cids: vector::empty(),
            total_bookings: 0,
            total_spent: 0,
            total_earned: 0,
        });
        
        // Update registry
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        table::add(&mut registry.users, user_addr, true);
        
        if (role == ROLE_STUDENT) {
            registry.total_students = registry.total_students + 1;
        } else if (role == ROLE_BARBER) {
            registry.total_barbers = registry.total_barbers + 1;
        } else if (role == ROLE_ADMIN) {
            registry.total_admins = registry.total_admins + 1;
        };
        
        // Emit event
        event::emit_event(&mut registry.user_registered_events, UserRegisteredEvent {
            user_address: user_addr,
            campus_domain,
            role,
            timestamp: timestamp::now_seconds(),
        });
    }

    // ═══════════════════════════════════════════════════════════
    //  BALANCE MANAGEMENT
    // ═══════════════════════════════════════════════════════════

    /// Deposit funds into user's available balance
    /// Platform calls this after receiving fiat payment
    public entry fun deposit(
        platform: &signer,
        user_addr: address,
        amount: u64,
    ) acquires UserAccount, UserRegistry {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        let available_before = account.balance_available;
        account.balance_available = account.balance_available + amount;
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.balance_updated_events, BalanceUpdatedEvent {
            user_address: user_addr,
            available_before,
            available_after: account.balance_available,
            locked_before: account.balance_locked,
            locked_after: account.balance_locked,
            reason: string::utf8(b"deposit"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Lock funds for escrow (called when creating booking)
    public entry fun lock_balance(
        platform: &signer,
        user_addr: address,
        amount: u64,
    ) acquires UserAccount, UserRegistry {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        assert!(account.balance_available >= amount, E_INSUFFICIENT_BALANCE);
        
        let available_before = account.balance_available;
        let locked_before = account.balance_locked;
        
        account.balance_available = account.balance_available - amount;
        account.balance_locked = account.balance_locked + amount;
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.balance_updated_events, BalanceUpdatedEvent {
            user_address: user_addr,
            available_before,
            available_after: account.balance_available,
            locked_before,
            locked_after: account.balance_locked,
            reason: string::utf8(b"escrow_lock"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Release locked funds to recipient (called when booking completes)
    public entry fun release_locked_to(
        platform: &signer,
        from_addr: address,
        to_addr: address,
        amount: u64,
    ) acquires UserAccount, UserRegistry {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(exists<UserAccount>(from_addr), E_NOT_REGISTERED);
        assert!(exists<UserAccount>(to_addr), E_NOT_REGISTERED);
        
        // Unlock from sender
        let from_account = borrow_global_mut<UserAccount>(from_addr);
        assert!(from_account.balance_locked >= amount, E_INSUFFICIENT_BALANCE);
        
        let locked_before = from_account.balance_locked;
        from_account.balance_locked = from_account.balance_locked - amount;
        from_account.total_spent = from_account.total_spent + amount;
        
        // Emit event for sender
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.balance_updated_events, BalanceUpdatedEvent {
            user_address: from_addr,
            available_before: from_account.balance_available,
            available_after: from_account.balance_available,
            locked_before,
            locked_after: from_account.balance_locked,
            reason: string::utf8(b"escrow_release"),
            timestamp: timestamp::now_seconds(),
        });
        
        // Credit to recipient
        let to_account = borrow_global_mut<UserAccount>(to_addr);
        let available_before = to_account.balance_available;
        to_account.balance_available = to_account.balance_available + amount;
        to_account.total_earned = to_account.total_earned + amount;
        
        // Emit event for recipient
        event::emit_event(&mut registry.balance_updated_events, BalanceUpdatedEvent {
            user_address: to_addr,
            available_before,
            available_after: to_account.balance_available,
            locked_before: to_account.balance_locked,
            locked_after: to_account.balance_locked,
            reason: string::utf8(b"payment_received"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Refund locked funds back to available (called when booking cancelled)
    public entry fun refund_locked(
        platform: &signer,
        user_addr: address,
        amount: u64,
    ) acquires UserAccount, UserRegistry {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        assert!(account.balance_locked >= amount, E_INSUFFICIENT_BALANCE);
        
        let available_before = account.balance_available;
        let locked_before = account.balance_locked;
        
        account.balance_locked = account.balance_locked - amount;
        account.balance_available = account.balance_available + amount;
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.balance_updated_events, BalanceUpdatedEvent {
            user_address: user_addr,
            available_before,
            available_after: account.balance_available,
            locked_before,
            locked_after: account.balance_locked,
            reason: string::utf8(b"refund"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Withdraw available balance (to bank account via platform)
    public entry fun withdraw(
        platform: &signer,
        user_addr: address,
        amount: u64,
    ) acquires UserAccount, UserRegistry {
        assert!(amount > 0, E_INVALID_AMOUNT);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        assert!(account.balance_available >= amount, E_INSUFFICIENT_BALANCE);
        
        let available_before = account.balance_available;
        account.balance_available = account.balance_available - amount;
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.balance_updated_events, BalanceUpdatedEvent {
            user_address: user_addr,
            available_before,
            available_after: account.balance_available,
            locked_before: account.balance_locked,
            locked_after: account.balance_locked,
            reason: string::utf8(b"withdrawal"),
            timestamp: timestamp::now_seconds(),
        });
        
        // Platform handles actual fiat transfer off-chain
    }

    // ═══════════════════════════════════════════════════════════
    //  PROFILE MANAGEMENT
    // ═══════════════════════════════════════════════════════════

    /// Update profile photo (IPFS CID)
    public entry fun update_profile_photo(
        user: &signer,
        ipfs_cid: String,
    ) acquires UserAccount, UserRegistry {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        account.profile_photo_cid = ipfs_cid;
        account.last_active = timestamp::now_seconds();
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.profile_updated_events, ProfileUpdatedEvent {
            user_address: user_addr,
            field: string::utf8(b"profile_photo"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update bio
    public entry fun update_bio(
        user: &signer,
        bio: String,
    ) acquires UserAccount, UserRegistry {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        account.bio = bio;
        account.last_active = timestamp::now_seconds();
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.profile_updated_events, ProfileUpdatedEvent {
            user_address: user_addr,
            field: string::utf8(b"bio"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update username
    public entry fun update_username(
        user: &signer,
        username: String,
    ) acquires UserAccount, UserRegistry {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        account.username = username;
        account.last_active = timestamp::now_seconds();
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.profile_updated_events, ProfileUpdatedEvent {
            user_address: user_addr,
            field: string::utf8(b"username"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Add portfolio image (barbers only)
    public entry fun add_portfolio_image(
        user: &signer,
        ipfs_cid: String,
    ) acquires UserAccount, UserRegistry {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        assert!(account.role == ROLE_BARBER, E_UNAUTHORIZED);
        
        vector::push_back(&mut account.portfolio_cids, ipfs_cid);
        account.last_active = timestamp::now_seconds();
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.profile_updated_events, ProfileUpdatedEvent {
            user_address: user_addr,
            field: string::utf8(b"portfolio"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Update barber specialties
    public entry fun update_specialties(
        user: &signer,
        specialties: vector<String>,
    ) acquires UserAccount, UserRegistry {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        assert!(account.role == ROLE_BARBER, E_UNAUTHORIZED);
        
        account.specialties = specialties;
        account.last_active = timestamp::now_seconds();
        
        // Emit event
        let registry = borrow_global_mut<UserRegistry>(@campus_cuts);
        event::emit_event(&mut registry.profile_updated_events, ProfileUpdatedEvent {
            user_address: user_addr,
            field: string::utf8(b"specialties"),
            timestamp: timestamp::now_seconds(),
        });
    }

    /// Toggle instant booking (barbers only)
    public entry fun toggle_instant_book(
        user: &signer,
        enabled: bool,
    ) acquires UserAccount {
        let user_addr = signer::address_of(user);
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        
        let account = borrow_global_mut<UserAccount>(user_addr);
        assert!(account.role == ROLE_BARBER, E_UNAUTHORIZED);
        
        account.instant_book_enabled = enabled;
        account.last_active = timestamp::now_seconds();
    }

    // ═══════════════════════════════════════════════════════════
    //  VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════

    #[view]
    public fun get_user_balance(user_addr: address): (u64, u64) acquires UserAccount {
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        let account = borrow_global<UserAccount>(user_addr);
        (account.balance_available, account.balance_locked)
    }

    #[view]
    public fun is_registered(user_addr: address): bool {
        exists<UserAccount>(user_addr)
    }

    #[view]
    public fun get_user_role(user_addr: address): u8 acquires UserAccount {
        assert!(exists<UserAccount>(user_addr), E_NOT_REGISTERED);
        borrow_global<UserAccount>(user_addr).role
    }

    #[view]
    public fun is_barber(user_addr: address): bool acquires UserAccount {
        if (!exists<UserAccount>(user_addr)) {
            return false
        };
        borrow_global<UserAccount>(user_addr).role == ROLE_BARBER
    }

    #[view]
    public fun get_total_users(): (u64, u64, u64) acquires UserRegistry {
        let registry = borrow_global<UserRegistry>(@campus_cuts);
        (registry.total_students, registry.total_barbers, registry.total_admins)
    }
}

