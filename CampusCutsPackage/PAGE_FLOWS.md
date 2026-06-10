# CampusCut Page Flows Documentation

This document explains the user flow through the main pages of the CampusCut platform.

---

## Table of Contents
1. [Landing Page](#1-landing-page)
2. [Login / Signup Pages](#2-login--signup-pages)
3. [Consumer Page](#3-consumer-page)
4. [Barber Page](#4-barber-page)

---

## 1. Landing Page

**Route:** `/`  
**File:** `web-app/src/pages/LandingPage.tsx`

### Purpose
The Landing Page is the public-facing homepage that introduces CampusCut to new visitors. It allows users to discover barbers at their university without requiring authentication.

### Key Features

1. **University Selector (Hero Section)**
   - Search dropdown to find your university
   - Selecting a university enables the "Find Barber" button
   - University selection is saved to `localStorage` for persistence

2. **Find Barber Button**
   - Navigates unauthenticated users to `/web/consumer` (discovery mode)
   - University context is carried through localStorage

3. **Navigation Menu**
   - **See Our Work** - Scrolls to embedded YouTube shorts showcasing haircuts
   - **Campus Manager** - Displays the Campus Manager for selected campuses
   - **Pricing Explained** - Comparison of traditional barbershop vs CampusCut economics
   - **FAQ** - Tabbed FAQ for Consumers and Barbers

4. **Call-to-Action Buttons**
   - **Sign In** (header) → Navigates to `/web` (AuthPage)
   - **Become a Barber** (footer) → Opens Barber Application Modal (guest mode)

### User Flow

```
┌─────────────────────────────────────────────────────────────┐
│                      Landing Page (/)                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌───────────────────────────────────────────────────┐    │
│   │         Select Your University                     │    │
│   │   ┌─────────────────────────────────────────┐     │    │
│   │   │  🔍 Search for your university...       │     │    │
│   │   └─────────────────────────────────────────┘     │    │
│   └───────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│              ┌────────────────────────┐                     │
│              │     Find Barber        │  (disabled until    │
│              │   (Large CTA Button)   │   university        │
│              └────────────────────────┘   selected)         │
│                           │                                 │
│                           ▼                                 │
│                   /web/consumer                             │
│             (Consumer Discovery Page)                       │
└─────────────────────────────────────────────────────────────┘
```

---

## 2. Login / Signup Pages

### Login Page

**Route:** `/web` or `/web/auth`  
**File:** `web-app/src/pages/auth/LoginPage.tsx`

### Purpose
Authenticate existing users and redirect them based on their role.

### Key Features

1. **Email & Password Fields**
   - Email validation with real-time checkmark/X icon
   - Password visibility toggle
   - Form validation prevents submission until valid

2. **Error Handling**
   - Rate limit detection
   - "Account not found" → suggests signup
   - "Invalid password" → retry prompt

3. **Post-Login Redirect Logic**
   ```typescript
   if (isAdmin || isCampusManager || user_type === 'barber') {
     navigate('/web/barber');  // Barber Dashboard
   } else {
     navigate('/web/consumer'); // Consumer Discovery
   }
   ```

4. **Footer Links**
   - "Forgot your password?" → Password reset
   - "Sign up" → Signup page
   - "Contact Support" → Email link

### User Flow

```
┌─────────────────────────────────────────────────────────────┐
│                     Login Page (/web)                        │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌───────────────────────────────────────────────────┐    │
│   │  Email: [_____________________________] ✓         │    │
│   │  Password: [_____________________] 👁              │    │
│   │                                                    │    │
│   │         ┌──────────────────────┐                  │    │
│   │         │      Sign In         │                  │    │
│   │         └──────────────────────┘                  │    │
│   └───────────────────────────────────────────────────┘    │
│                           │                                 │
│           ┌───────────────┴───────────────┐                │
│           │                               │                 │
│     ┌─────▼─────┐                 ┌───────▼───────┐        │
│     │  Barber?  │                 │   Consumer?   │        │
│     │   Admin?  │                 │   Student?    │        │
│     │  Manager? │                 │               │        │
│     └─────┬─────┘                 └───────┬───────┘        │
│           │                               │                 │
│           ▼                               ▼                 │
│    /web/barber                     /web/consumer            │
└─────────────────────────────────────────────────────────────┘
```

---

### Signup Page

**Route:** `/web/signup`  
**File:** `web-app/src/pages/auth/SignupPage.tsx`

### Purpose
Create new user accounts with email verification and Terms of Service acceptance.

### Key Features

1. **Form Fields**
   - First Name / Last Name
   - Email (any email allowed, validates format)
   - Password with strength meter (Weak → Very Strong)
   - Confirm Password with match indicator

2. **Terms of Service Agreement**
   - User must click to view full Terms
   - Must scroll to bottom to enable "Accept" button
   - Cannot submit form without accepting

3. **Password Strength Indicator**
   ```
   Checks: length ≥8, lowercase, uppercase, number, special char
   Score:  1-5 displayed as colored bars
   Labels: Weak → Fair → Good → Strong → Very Strong
   ```

4. **Post-Signup Flow**
   - Success → Navigate to `/web/verify-email`
   - Verification email sent to user's email address
   - In dev mode, verification code is shown in toast

### User Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   Signup Page (/web/signup)                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│   ┌───────────────────────────────────────────────────┐    │
│   │  First Name: [________]  Last Name: [________]    │    │
│   │  Email: [_________________________________] ✓     │    │
│   │  Password: [________________________] 👁           │    │
│   │    Strength: [███░░] Good                         │    │
│   │  Confirm: [_________________________] ✓           │    │
│   │                                                    │    │
│   │  ☐ I agree to Terms of Service                    │    │
│   │     └─> Opens Modal (must scroll to accept)       │    │
│   │                                                    │    │
│   │         ┌──────────────────────┐                  │    │
│   │         │   Create Account     │                  │    │
│   │         └──────────────────────┘                  │    │
│   └───────────────────────────────────────────────────┘    │
│                           │                                 │
│                           ▼                                 │
│                  /web/verify-email                          │
│            (Enter 6-digit code from email)                  │
│                           │                                 │
│                           ▼                                 │
│                  /web/consumer                              │
│              (All users start as consumers)                 │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. Consumer Page

**Route:** `/web/consumer`  
**File:** `web-app/src/pages/ConsumerPage.tsx`

### Purpose
The main discovery and booking interface for consumers (students) to find and book barbers.

### Key Features

1. **Header**
   - **Left:** "Barber View" button (if user is barber) OR "Become a Barber" button
   - **Center:** CampusCut logo (clickable → Landing Page)
   - **Right:** Messages icon + Profile dropdown (authenticated) OR "Sign In" button (guest)

2. **Profile Dropdown (Authenticated Users)**
   - Notifications (with unread count)
   - Edit Profile → Opens modal with profile settings + Delete Account
   - Sign Out

3. **Discovery View**
   - Shows barbers at the selected university
   - Barber cards display: Name, Photo, Price range, Instagram handle
   - Responsive grid: 1 column (mobile) → 2-5 columns (tablet/desktop)

4. **Barber Profile Modal** (click any barber card)
   - Profile picture, name, Instagram link
   - Services with prices
   - Weekly availability schedule
   - Service locations
   - Bio/About section
   - **"Schedule Service" button** → Booking flow

5. **Active Booking Detection**
   - On load, checks for PENDING or ACCEPTED bookings
   - If found, auto-redirects to `/web/consumer/booking-status`

6. **Real-time WebSocket Events**
   - `booking-completed`: Shows payment modal when barber completes service
   - Updates notifications count

### User Flow

```
┌─────────────────────────────────────────────────────────────┐
│              Consumer Page (/web/consumer)                   │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    [CampusCut Logo]    💬 [Profile ▼]     │
│  │Become Barber│                                            │
│  └─────────────┘                                            │
├─────────────────────────────────────────────────────────────┤
│  Barbers at Cal Poly SLO • 7 barbers found                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │  Photo   │  │  Photo   │  │  Photo   │  │  Photo   │   │
│  │──────────│  │──────────│  │──────────│  │──────────│   │
│  │ Justin   │  │   Ty     │  │  Niko    │  │  Jaden   │   │
│  │  $30     │  │  $25     │  │  $28     │  │  $25     │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│        │                                                    │
│        ▼ (click)                                            │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              BARBER PROFILE MODAL                    │   │
│  │  ┌────────┐  Justin Schroeter  [@instagram]          │   │
│  │  │ Photo  │                                          │   │
│  │  └────────┘  Services: Haircut $30, Fade $30         │   │
│  │              Availability: Mon 9am-5pm, Tue 10am-6pm │   │
│  │              Locations: Sierra Madre, Red Bricks     │   │
│  │              About: "Professional barber..."         │   │
│  │              ┌─────────────────────────────────┐     │   │
│  │              │      Schedule Service           │     │   │
│  │              └─────────────────────────────────┘     │   │
│  └─────────────────────────────────────────────────────┘   │
│                           │                                 │
│                           ▼                                 │
│             /web/consumer/book/:barberId                    │
│                   (Booking Form)                            │
└─────────────────────────────────────────────────────────────┘
```

### Booking Flow After Schedule Click

```
/web/consumer/book/:barberId → Select service, date, time, location
           │
           ▼
      Submit Request → Booking created with status: PENDING
           │
           ▼
   /web/consumer/booking-status → Wait for barber to accept/decline
           │
      ┌────┴────┐
      │         │
   ACCEPTED   DECLINED
      │         │
      ▼         ▼
 Wait for    Return to
 service     consumer
 completion  (can rebook)
      │
      ▼
 Barber marks COMPLETE
      │
      ▼
 Payment Modal appears (or /web/payment/:bookingId)
      │
      ▼
 Pay via Card/Apple Pay OR Cash
      │
      ▼
 Status → PAID, Leave review
```

---

## 4. Barber Page

**Route:** `/web/barber`  
**File:** `web-app/src/pages/BarberPage.tsx`

### Purpose
The main dashboard for barbers to manage their business: bookings, availability, services, earnings, and profile.

### Key Features

1. **Header**
   - **Left:** "Consumer View" button → Switch to consumer mode
   - **Center:** CampusCut logo
   - **Right:** Messages, Notifications, Profile dropdown

2. **Stripe Connect Check**
   - On load, checks if barber has completed Stripe Connect onboarding
   - If NOT completed → Forces "Payout Settings" modal open
   - Cannot use dashboard until Stripe is connected

3. **Profile Dropdown**
   - Edit Profile
   - Services & Pricing
   - My Availability
   - My Locations
   - Payout Settings
   - **Campus Manager** (if user is campus manager)
   - Sign Out

4. **Main Dashboard Content**
   - **Booking Requests Dropdown:** Shows pending/accepted bookings
   - **Quick Stats:** Today's bookings, earnings, etc.
   - **Recent Activity:** Last few completed services
   - **Visibility Toggle:** Show/hide profile from consumers

5. **Modal Features**
   - **Profile Editor:** Update bio, profile picture, Instagram
   - **Services & Pricing:** Add/edit services with custom prices
   - **Availability:** Set weekly schedule with multi-interval support
   - **Locations:** Add/remove service locations on campus
   - **Payout Settings:** Stripe Connect status and onboarding

6. **Campus Manager Dashboard** (if user.is_campus_manager)
   - Manage barbers at your campus
   - View/approve barber applications
   - See all campus bookings (upcoming/completed)
   - Toggle barber visibility

7. **Real-time WebSocket Events**
   - `new-booking-request`: Toast + notification when consumer books
   - `payment-received`: Toast when consumer pays (card or cash)
   - Updates booking list in real-time

### User Flow

```
┌─────────────────────────────────────────────────────────────┐
│              Barber Page (/web/barber)                       │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    [CampusCut Logo]    💬 🔔 [Profile ▼]  │
│  │Consumer View│                                            │
│  └─────────────┘                                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  📥 Booking Requests (3)                        ▼   │   │
│  └─────────────────────────────────────────────────────┘   │
│        │                                                    │
│        ▼ (expand)                                           │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ ┌────────────────────────────────────────────────┐  │   │
│  │ │ PENDING | Liam McKeown | Haircut | Feb 8 3pm   │  │   │
│  │ │         [Accept]  [Decline]  [Message]         │  │   │
│  │ └────────────────────────────────────────────────┘  │   │
│  │ ┌────────────────────────────────────────────────┐  │   │
│  │ │ ACCEPTED | Jack M. | Fade | Feb 10 2pm         │  │   │
│  │ │         [Mark Complete]  [Message]             │  │   │
│  │ └────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Quick Actions                                       │   │
│  │  [Services & Pricing] [Availability] [Locations]     │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Profile Visibility: [ON/OFF Toggle]                 │   │
│  │  (Hidden = not shown to consumers)                   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### Booking Lifecycle (Barber Perspective)

```
1. Consumer submits booking request
           │
           ▼
2. Barber sees notification + request in dropdown
           │
      ┌────┴────────────────┐
      │                     │
   [Accept]              [Decline]
      │                     │
      ▼                     ▼
3. Status: ACCEPTED    Status: DECLINED
   Consumer notified    Consumer notified
      │                 (flow ends)
      ▼
4. Barber performs service
      │
      ▼
5. [Mark Complete] button clicked
      │
      ▼
6. Status: COMPLETED (awaiting payment)
   Consumer receives payment request
      │
      ▼
7. Consumer pays (Card/Apple Pay/Cash)
      │
      ▼
8. Status: PAID
   Barber receives earnings via Stripe
   Consumer can leave review
```

---

## Route Summary

| Route | Page | Access |
|-------|------|--------|
| `/` | Landing Page | Public |
| `/web` | Login Page | Public |
| `/web/signup` | Signup Page | Public |
| `/web/verify-email` | Email Verification | Public |
| `/web/consumer` | Consumer Discovery | Guest + Auth |
| `/web/consumer/book/:id` | Booking Form | Auth Only |
| `/web/consumer/booking-status` | Booking Status | Auth Only |
| `/web/consumer/messages` | Consumer Messages | Auth Only |
| `/web/payment/:id` | Post-Service Payment | Auth Only |
| `/web/barber` | Barber Dashboard | Barbers Only |
| `/web/barber/messages` | Barber Messages | Barbers Only |
| `/web/barber/earnings` | Earnings History | Barbers Only |
| `/terms` | Terms of Service | Public |
| `/privacy` | Privacy Policy | Public |

---

## Authentication State

| State | Can Access |
|-------|------------|
| Unauthenticated | Landing, Login, Signup, Consumer Discovery (view only) |
| Authenticated (Consumer) | All consumer pages, can apply to be barber |
| Authenticated (Barber) | All consumer + barber pages |
| Authenticated (Campus Manager) | All barber pages + Campus Manager dashboard |
| Authenticated (Admin) | Same as Campus Manager (platform-wide) |

---

*Document generated: February 2026*
*CampusCut v2.0.0*


