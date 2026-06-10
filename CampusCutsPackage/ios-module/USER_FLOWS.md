# CampusCuts iOS User Flows

> Detailed documentation of consumer and barber user journeys for the native iOS app.

---

## Table of Contents

1. [App Entry & Authentication](#app-entry--authentication)
2. [Consumer Experience](#consumer-experience)
3. [Barber Experience](#barber-experience)
4. [Shared Features](#shared-features)
5. [Screen-by-Screen Specifications](#screen-by-screen-specifications)

---

## App Entry & Authentication

### First Launch (Unauthenticated)

When a user opens the app for the first time:

```
App Launch
    ↓
Auth Check (JWT token in Keychain?)
    ↓
[No Token] → Auth Screen
    ↓
    ├── Sign In (Email + Password)
    ├── Sign Up (Email + Password + Name)
    └── Google Sign-In (Optional)
    ↓
[Success] → Role-Based Routing
```

### Role-Based Routing

After authentication, route users based on their role:

```swift
switch user.userType {
case .student:
    // Check for active booking first
    if hasActiveBooking {
        navigate(to: .bookingStatus)
    } else {
        navigate(to: .consumerHome)
    }
    
case .barber, .campusManager, .admin:
    navigate(to: .barberDashboard)
}
```

### Session Persistence

- Store JWT token securely in iOS Keychain
- On app launch, validate token with backend
- If token expired, attempt silent refresh
- If refresh fails, redirect to Auth Screen

---

## Consumer Experience

### Consumer Home Screen

**What the consumer sees upon opening the app:**

```
┌─────────────────────────────────────┐
│ [Header]                            │
│  Logo (center)                      │
│  Profile Avatar (right) → Dropdown  │
├─────────────────────────────────────┤
│ [Tab Picker]                        │
│  [ Browse ]  [ My Bookings (2) ]    │
├─────────────────────────────────────┤
│ [Search Bar]                        │
│  🔍 Search barbers...               │
├─────────────────────────────────────┤
│ [Barber List - Scrollable]          │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ 👤 Business Name      🟢 >  │    │
│  │    Bio snippet...           │    │
│  │    ⭐ 4.8  •  42 cuts       │    │
│  └─────────────────────────────┘    │
│                                     │
│  ┌─────────────────────────────┐    │
│  │ 👤 Another Barber       >   │    │
│  │    Bio snippet...           │    │
│  │    ⭐ 4.5  •  28 cuts       │    │
│  └─────────────────────────────┘    │
│                                     │
│  (Pull to refresh)                  │
└─────────────────────────────────────┘
```

### Consumer Flow: Browsing to Booking

```
Consumer Home (Browse Tab)
    ↓
[Tap Barber Card]
    ↓
Barber Profile Screen
    ├── Profile photo, name, bio
    ├── Instagram portfolio link
    ├── Services & prices list
    ├── Availability schedule
    ├── Reviews (star ratings)
    └── [Book Now] button
    ↓
[Tap Book Now]
    ↓
Schedule Service Screen
    ├── Select Service (dropdown)
    │   - Service name + price shown
    ├── Select Date (date picker)
    │   - Min date: today
    │   - Shows availability
    ├── Select Time (time picker)
    │   - Only available slots shown
    │   - 15-minute increments
    ├── Select Location (from barber's locations)
    ├── Add Notes (optional textarea)
    └── [Submit Request] button
    ↓
[Tap Submit Request]
    ↓
API: POST /bookings
    ↓
Navigate to Booking Status Screen
```

### Booking Status Screen

Once a consumer has an active booking (PENDING or ACCEPTED), they're redirected here:

```
┌─────────────────────────────────────┐
│ [Header]                            │
│  Logo (center)                      │
│  Profile Avatar (right)             │
├─────────────────────────────────────┤
│                                     │
│  [Status Card]                      │
│  ┌─────────────────────────────┐    │
│  │      ⏳ Pending             │    │
│  │  Waiting for barber...     │    │
│  │                             │    │
│  │  or                         │    │
│  │                             │    │
│  │      ✓ Accepted            │    │
│  │  Your appointment is       │    │
│  │  confirmed!                │    │
│  └─────────────────────────────┘    │
│                                     │
│  [Booking Details]                  │
│  ┌─────────────────────────────┐    │
│  │ 👤 Barber Name              │    │
│  │ ✂️ Service: Haircut         │    │
│  │ 📅 March 15, 2026           │    │
│  │ 🕐 2:00 PM                  │    │
│  │ 📍 Location Name            │    │
│  │ 💵 $30.00                   │    │
│  └─────────────────────────────┘    │
│                                     │
│  [Actions]                          │
│  ┌─────────────────────────────┐    │
│  │  💬 Message Barber          │    │
│  │  ✏️ Edit Booking            │    │
│  │  ❌ Cancel Booking          │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

### Booking States

| State | UI | Actions Available |
|-------|----|--------------------|
| PENDING | Yellow/Orange badge, "Waiting for barber" | Edit, Cancel, Message |
| ACCEPTED | Blue badge, "Confirmed!" | Edit, Cancel, Message |
| COMPLETED | Green badge, "Service complete" | Pay (redirects to payment) |
| CANCELLED | Red badge, "Cancelled" | Book again (back to browse) |

### Payment Flow (After Service)

```
Barber marks booking as COMPLETED
    ↓
[WebSocket Event] → Consumer receives notification
    ↓
Payment Modal appears OR navigate to Payment Screen
    ↓
Payment Screen
    ├── Service summary
    ├── Amount due
    ├── Tip selection (15%, 20%, 25%, Custom)
    ├── Payment method (Apple Pay, Card)
    └── [Pay Now] button
    ↓
[Tap Pay Now]
    ↓
Stripe Payment Sheet
    ↓
[Success]
    ↓
Review Prompt (optional)
    ├── Star rating (1-5)
    └── Comment (optional)
    ↓
Navigate back to Consumer Home
```

### My Bookings Tab

Shows booking history:

```
┌─────────────────────────────────────┐
│ [Tab Picker]                        │
│  [ Browse ]  [My Bookings ✓]        │
├─────────────────────────────────────┤
│                                     │
│  UPCOMING                           │
│  ┌─────────────────────────────┐    │
│  │ 👤 Barber Name     [Accept] │    │
│  │ ✂️ Haircut  •  Mar 15       │    │
│  │ 🕐 2:00 PM  •  $30.00       │    │
│  │            [Cancel]         │    │
│  └─────────────────────────────┘    │
│                                     │
│  PAST                               │
│  ┌─────────────────────────────┐    │
│  │ 👤 Barber Name   [Complete] │    │
│  │ ✂️ Haircut  •  Mar 10       │    │
│  │ 🕐 3:00 PM  •  $35.00       │    │
│  └─────────────────────────────┘    │
│                                     │
└─────────────────────────────────────┘
```

---

## Barber Experience

### Barber Dashboard

**What the barber sees upon opening the app:**

```
┌─────────────────────────────────────┐
│ [Header]                            │
│  [Chats 💬]  Logo  [Inbox 📥(3)] 👤 │
├─────────────────────────────────────┤
│ [View Toggle]                       │
│  [Daily ✓] [Weekly] [Monthly]       │
├─────────────────────────────────────┤
│ [Date Navigator]                    │
│  ◀ Today - Monday, March 10 ▶      │
│     2 appointments                  │
├─────────────────────────────────────┤
│ [Availability Slots]                │
│                                     │
│  ✓ 9:00 AM - 10:00 AM  (available) │
│  ✓ 10:00 AM - 11:00 AM (available) │
│  ■ 11:00 AM - 12:00 PM (blocked)   │
│  📅 12:00 PM - 1:00 PM  (booked)   │
│     John D. - Haircut              │
│  ✓ 1:00 PM - 2:00 PM   (available) │
│  📅 2:00 PM - 3:00 PM   (booked)   │
│     Mike S. - Fade                 │
│                                     │
│  [Edit Availability]                │
│                                     │
└─────────────────────────────────────┘
```

### Barber Flow: Managing Booking Requests

```
Notification: "New booking request from John"
    ↓
[Tap notification OR tap Inbox]
    ↓
Booking Requests Dropdown/Screen
    ├── List of pending requests
    └── Each request shows:
        - Customer name
        - Service requested
        - Date/Time
        - Location
        - [Accept] [Decline] buttons
    ↓
[Tap Accept]
    ↓
API: PATCH /bookings/:id/status
    ↓
Booking moves to "Upcoming"
Customer receives notification
```

### Barber Flow: Completing a Service

```
Appointment time arrives
    ↓
Customer arrives, service performed
    ↓
Barber Dashboard → Tap booked slot
    ↓
Booking Details Modal
    ├── Customer info
    ├── Service details
    ├── [Mark Complete] button
    └── [Cancel Booking] (with reason)
    ↓
[Tap Mark Complete]
    ↓
Confirmation: "Mark as complete?"
    ↓
[Confirm]
    ↓
API: PATCH /bookings/:id/status → COMPLETED
    ↓
WebSocket notifies customer → Payment requested
    ↓
Customer pays → Funds to barber's Stripe
```

### Barber Profile Dropdown Menu

```
┌─────────────────────────┐
│ Switch to Consumer      │ ← If barber wants to book with another barber
├─────────────────────────┤
│ Edit Profile            │ ← Bio, photo, Instagram
│ Services                │ ← Add/edit services & prices
│ Locations               │ ← Manage service locations
│ Bookings                │ ← View all bookings
│ Availability            │ ← Set weekly schedule
│ Block Time              │ ← Block specific dates/times
│ Notifications           │ ← View notifications
│ Payout Settings         │ ← Connect/manage Stripe
├─────────────────────────┤
│ Privacy Policy          │
│ Terms of Service        │
├─────────────────────────┤
│ Sign Out                │ ← Red, destructive
└─────────────────────────┘
```

### Barber Settings Screens

#### Edit Profile
- Profile photo (camera/library)
- Business name
- Bio (text area)
- Instagram handle
- Years of experience

#### Services & Pricing
- List of offered services
- Each service: name, description, price, duration
- Add new service
- Edit/delete existing

#### Locations
- List of service locations
- Each: name, description, address
- Add new location
- Edit/delete existing
- Set primary location

#### Availability (Weekly Schedule)
- 7 days (Mon-Sun)
- Each day:
  - Toggle enabled/disabled
  - Multiple time intervals (Calendly-style)
  - Add/remove intervals
- Example: Mon 9am-12pm, 2pm-6pm

#### Block Time
- Select specific date
- Select start/end time
- Reason (optional)
- Creates one-time block

#### Payout Settings
- Stripe Connect status
- If not connected: [Connect Stripe] button → OAuth flow
- If connected: Account status, payout schedule

---

## Shared Features

### Messaging

Both consumers and barbers can message each other:

```
Messages Screen
    ↓
[Conversation List]
    ├── Recent conversations
    ├── Each shows: avatar, name, last message, timestamp
    └── Unread indicator
    ↓
[Tap Conversation]
    ↓
Chat Screen
    ├── Message bubbles (sent/received)
    ├── Timestamps
    └── Input field + Send button
```

### Notifications

```
Notifications Screen
    ↓
[Filter Tabs]
    All | Bookings | Payments | Reviews | Messages
    ↓
[Notification List]
    ├── Icon based on type
    ├── Title + description
    ├── Timestamp
    ├── Read/unread indicator
    └── [Mark all as read] action
```

### Profile Dropdown (Both Roles)

Common items:
- Messages
- Notifications  
- Privacy Policy
- Terms of Service
- Sign Out

---

## Screen-by-Screen Specifications

### 1. Auth Screen

**Purpose:** Sign in or sign up

**Elements:**
- Logo at top
- Tab toggle: Sign In / Sign Up
- Email input field
- Password input field
- [Sign Up only] First name, Last name
- Primary button: "Sign In" or "Create Account"
- Social login option (Google)
- Forgot password link

**Actions:**
- Validate inputs
- API call to authenticate
- Store token in Keychain
- Navigate to appropriate home screen

---

### 2. Consumer Home Screen

**Purpose:** Browse barbers and manage bookings

**Header:**
- CampusCuts logo (center)
- Profile avatar button (right) → dropdown

**Tab Picker:**
- "Browse" tab (default)
- "My Bookings" tab (with badge count)

**Browse Tab Content:**
- Search bar with magnifying glass icon
- Scrollable list of Barber Cards
- Pull-to-refresh enabled
- Empty state if no barbers

**My Bookings Tab Content:**
- "Upcoming" section header
- List of upcoming booking cards
- "Past" section header
- List of past booking cards
- Empty state if no bookings

---

### 3. Barber Profile Screen

**Purpose:** View barber details before booking

**Header:**
- Back button (left)
- "Book" button (right, optional)

**Content:**
- Large profile photo
- Business name (headline)
- Star rating + review count
- Bio text
- Instagram link (opens Instagram app/web)

**Services Section:**
- List of services with prices
- Each: service name, duration, price

**Availability Section:**
- Weekly schedule display
- Days with hours

**Reviews Section:**
- Recent reviews (3-5)
- Each: star rating, comment, date, customer name
- "See all reviews" link

**Footer:**
- [Book Now] primary button (sticky)

---

### 4. Schedule Service Screen

**Purpose:** Select service details for booking

**Header:**
- Back button
- "Schedule with [Barber Name]"

**Form Fields:**
1. **Service Type** (required)
   - Dropdown/picker
   - Shows service name + price

2. **Date** (required)
   - Date picker
   - Disabled past dates
   - Visual availability indicators

3. **Time** (required)
   - Time picker dropdown
   - Only shows available slots
   - 15-minute increments

4. **Location** (required)
   - Picker with barber's locations
   - Auto-selects primary location

5. **Notes** (optional)
   - Text area
   - "Special requests or reference photos"

**Footer:**
- Total price display
- [Submit Request] primary button

**Validation:**
- All required fields must be filled
- Show inline errors
- Toast for submission errors

---

### 5. Booking Status Screen

**Purpose:** Track active booking

**Header:**
- Back button (to browse)
- Profile avatar

**Status Card:**
- Large status icon (animated)
- Status text (Pending/Accepted)
- Contextual message

**Booking Details Card:**
- Barber avatar + name
- Service name
- Date (formatted nicely)
- Time
- Location
- Price

**Action Buttons:**
- 💬 Message Barber
- ✏️ Edit Booking (opens edit modal)
- ❌ Cancel Booking (confirmation required)

**Edit Modal:**
- Same fields as schedule screen
- Pre-filled with current values
- [Save Changes] button

**Cancel Confirmation:**
- "Are you sure?" message
- Optional reason field
- [Cancel Booking] destructive button
- [Keep Booking] secondary button

---

### 6. Payment Screen

**Purpose:** Pay for completed service

**Header:**
- "Payment"
- Close button (if dismissible)

**Summary Card:**
- Barber name + avatar
- Service name
- Date/time of service
- Service price

**Tip Section:**
- "Add a tip for [Barber]?"
- Preset buttons: 15%, 20%, 25%
- Custom amount option
- Selected tip highlighted

**Total:**
- Service: $30.00
- Tip: $6.00
- Total: $36.00

**Payment Options:**
- Apple Pay button (if available)
- Pay with Card button

**Stripe Payment Sheet:**
- Opens native Stripe UI
- Card input
- Confirm payment

**Success State:**
- Checkmark animation
- "Payment successful!"
- [Leave a Review] button
- [Done] button

---

### 7. Barber Dashboard Screen

**Purpose:** Manage bookings and availability

**Header:**
- Chats button (left) with badge
- Logo (center)
- Inbox button with badge (booking requests)
- Profile avatar (right) → dropdown

**View Toggle:**
- Daily / Weekly / Monthly
- Default: Daily

**Date Navigator:**
- Previous button (◀)
- Current date display
- Today button
- Next button (▶)
- Appointment count

**Calendar/Schedule View:**

*Daily View:*
- Hour-by-hour timeline
- Color-coded slots:
  - Green: Available
  - Blue: Booked (shows customer + service)
  - Gray: Blocked
  - Red: Google Calendar busy
- Tap slot to view/edit

*Weekly View:*
- 7-day grid
- Each day shows appointments count
- Tap day to view details

*Monthly View:*
- Calendar grid
- Days with appointments marked
- Tap day to view

**Quick Actions:**
- Edit Availability button
- Block Time button (optional)

---

### 8. Booking Details Modal (Barber)

**Purpose:** View and manage individual booking

**Header:**
- "Booking Details"
- Close button

**Customer Info:**
- Avatar + name
- Service type
- Date/time
- Location
- Price
- Notes (if any)

**Status Badge:**
- Current status (Pending/Accepted/etc.)

**Actions (based on status):**

*If PENDING:*
- [Accept] primary button
- [Decline] secondary button (asks for reason)

*If ACCEPTED:*
- [Mark Complete] primary button
- [Cancel] secondary button
- [Edit Details] option

*If COMPLETED:*
- Payment status shown
- [Undo Complete] option (if payment not yet made)

---

### 9. Services & Pricing Screen (Barber)

**Purpose:** Manage offered services

**Header:**
- Back button
- "Services & Pricing"
- [+ Add] button

**Service List:**
- Each service card shows:
  - Service name
  - Description
  - Price
  - Duration
  - Edit/Delete buttons

**Add/Edit Service Modal:**
- Service name input
- Description textarea
- Price input ($ prefix)
- Duration picker (15min increments)
- [Save] / [Cancel] buttons

---

### 10. Availability Screen (Barber)

**Purpose:** Set weekly recurring schedule

**Header:**
- Back button
- "Availability"
- [Save] button

**Day List:**
For each day (Monday-Sunday):
```
┌─────────────────────────────────────┐
│ Monday                    [Toggle]  │
├─────────────────────────────────────┤
│ 9:00 AM - 12:00 PM           [✕]   │
│ 2:00 PM - 6:00 PM            [✕]   │
│ [+ Add interval]                    │
└─────────────────────────────────────┘
```

**Time Interval:**
- Start time picker
- End time picker
- Remove button (✕)

**Add Interval:**
- Opens time pickers
- Validates no overlap

---

## Real-Time Features

### WebSocket Events

The iOS app should listen for these WebSocket events:

| Event | Recipient | Action |
|-------|-----------|--------|
| `booking-created` | Barber | Show notification, update inbox |
| `booking-accepted` | Consumer | Update status, show toast |
| `booking-declined` | Consumer | Show modal with reason |
| `booking-completed` | Consumer | Show payment prompt |
| `booking-cancelled` | Both | Update UI, show reason |
| `booking-status-changed` | Both | Refresh booking data |
| `new-message` | Both | Update message badge, show preview |

### Push Notifications

Implement APNs for background notifications:

| Type | Title | Body |
|------|-------|------|
| New booking request | "New booking request" | "[Customer] wants a [Service]" |
| Booking accepted | "Booking confirmed!" | "[Barber] accepted your booking" |
| Booking declined | "Booking declined" | "[Barber] couldn't accept" |
| Payment requested | "Time to pay!" | "[Barber] completed your [Service]" |
| New message | "[Sender Name]" | "[Message preview...]" |
| Payment received | "Payment received" | "$[Amount] from [Customer]" |

---

## Data Models Quick Reference

```swift
struct User {
    let id: String
    let email: String
    let firstName: String
    let lastName: String
    let userType: UserType // student, barber, campusManager, admin
    let profilePictureUrl: String?
    let hasBarberProfile: Bool?
}

struct Barber {
    let id: String
    let userId: String
    let businessName: String
    let bio: String?
    let instagramHandle: String?
    let profileImageUrl: String?
    let rating: Double?
    let reviewCount: Int?
    let completedBookings: Int?
    let isAvailableNow: Bool?
    let services: [Service]
    let weeklySchedule: WeeklySchedule?
    let serviceLocations: [ServiceLocation]
}

struct Booking {
    let id: String
    let consumerId: String
    let barberId: String
    let serviceName: String
    let servicePrice: Double
    let scheduledTime: Date
    let location: String
    let status: BookingStatus
    let notes: String?
}

enum BookingStatus: String {
    case pending = "PENDING"
    case accepted = "ACCEPTED"
    case completed = "COMPLETED"
    case cancelled = "CANCELLED"
    case rejected = "REJECTED"
    case noShow = "NO_SHOW"
}
```

---

*Last updated: March 2026*
*Version: 1.0*

