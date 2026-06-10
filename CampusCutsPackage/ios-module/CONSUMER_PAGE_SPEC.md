# CampusCuts Consumer Page Specification

> iOS implementation guide for the Consumer Home experience.

---

## Overview

The Consumer Page is the main hub for students to browse and book barbers. 

**Entry Conditions:**
1. If no university selected → redirect to university selection
2. If active booking (PENDING/ACCEPTED) → redirect to Booking Status Page
3. Works for both authenticated and guest users

---

## Page Layout

```
┌─────────────────────────────────────────────────────┐
│ HEADER                                               │
│ [Become Barber]  [Logo]  [Messages 💬] [Profile ▼]  │
├─────────────────────────────────────────────────────┤
│ "Barbers at Cal Poly SLO • 5 found"  [Change]       │
├─────────────────────────────────────────────────────┤
│ BARBER GRID                                          │
│ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐        │
│ │ Photo  │ │ Photo  │ │ Photo  │ │ Photo  │        │
│ │ $25    │ │ $20-30 │ │ $35    │ │ $28    │        │
│ └────────┘ └────────┘ └────────┘ └────────┘        │
└─────────────────────────────────────────────────────┘
```

---

## Header

| Position | Unauthenticated | Consumer | Has Barber Profile |
|----------|-----------------|----------|-------------------|
| Left | "Become a Barber" | "Become a Barber" | "Barber View" |
| Center | Logo (tap → home) | Logo | Logo |
| Right | "Sign In" | Messages + Profile | Messages + Profile |

**Profile Dropdown:** Notifications, Edit Profile, Privacy/Terms, Sign Out

**"Become a Barber" Logic:**
- Not logged in → show login prompt
- Has pending application → show "Under Review" popup
- Has rejected application → show "Rejected" popup with "Apply Again" option
- Otherwise → show application form

---

## Barber Cards

**Portrait Mobile (Horizontal):**
```
┌─────────────────────────────────────┐
│ [Photo]  Business Name     $25  →  │
│  112px   @instagram_handle          │
└─────────────────────────────────────┘
```

**Tablet/Desktop (Vertical):**
```
┌───────────────────┐
│ [Business Name]   │ ← overlay
│                   │
│     Photo         │
│     224px         │
│                   │
│ [$25]             │ ← overlay
└───────────────────┘
```

**Interactions:** Tap → open profile modal, 98% scale on press

**Fair Ordering:** Barbers randomly shuffled on load (Fisher-Yates). Users cannot see their own barber profile.

---

## Barber Profile Modal

```
┌─────────────────────────────────────────┐
│ HEADER (sticky)                         │
│ "Business Name"      [@instagram] [×]   │
├─────────────────────────────────────────┤
│ [Photo]   SERVICES                      │
│  256px    [Haircut • $25] [Fade • $30]  │
│                                         │
│           AVAILABILITY                  │
│           Mon 9-5 | Tue 9-5 | Wed 9-5   │
│─────────────────────────────────────────│
│ LOCATIONS: [Dorm Room*] [Library]       │
│─────────────────────────────────────────│
│ ABOUT: "Bio text..."                    │
│─────────────────────────────────────────│
│ REVIEWS ▼  ⭐ 4.8 (42)                  │
│   John D. - Haircut - ⭐⭐⭐⭐⭐         │
│   "Great cut!"  Mar 5, 2026             │
├─────────────────────────────────────────┤
│ FOOTER (sticky)                         │
│ [      SCHEDULE SERVICE      ]          │
└─────────────────────────────────────────┘
```

**Schedule Click:** If not authenticated → show login prompt with redirect

---

## Modals Summary

| Modal | Trigger | Key Elements |
|-------|---------|--------------|
| Profile Editor | Profile dropdown | Photo, name, phone, [Delete Account] |
| Barber Application | "Become a Barber" | Business name, experience, Instagram, why join |
| Pending Popup | Click when pending app | "Under Review" message |
| Rejected Popup | Click when rejected | [Maybe Later] [Apply Again] |
| Login Prompt | Protected action | [Sign In] [Create Account] |
| Notifications | Profile dropdown | List with icons by type, [Mark all read] |
| Payment Request | WebSocket event | Amount due, [Pay Now] |
| Booking Declined | Notification tap | Reason shown, [Find Another Barber] |
| Alternative Barbers | Barber cancels | Original time, available barbers list |

**Notification Icons:**
- `booking_accepted`: ✓ Green
- `booking_rejected/cancelled`: ⚠️ Red  
- `new_message`: 💬 Primary
- `payment_request`: 💵 Primary

---

## State

```swift
// Main state
var selectedBarber: Barber?
var showProfileEditor/showNotifications/showPaymentModal: Bool
var hasPendingApplication/hasRejectedApplication: Bool
var notifications: [Notification]
var unreadNotifications/unreadMessages: Int

// Discovery state  
var barbers/filteredBarbers: [Barber]
var selectedUniversity: University?
var filterCriteria: FilterCriteria  // serviceType, date, time, location
var loading: Bool
```

---

## Real-Time

**WebSocket Events:**
- `booking-completed` → Show payment modal
- Connect on appear, disconnect on disappear

**On App Launch:** Check for active bookings → redirect to Booking Status if found

---

## Responsive Grid

| Viewport | Columns | Card Style |
|----------|---------|------------|
| Portrait Mobile | 1 | Horizontal |
| Landscape Mobile | 2 | Vertical |
| Tablet | 3 | Vertical |
| Desktop | 4-5 | Vertical |

**Pull-to-refresh:** Disabled when any modal is open

---

*Last updated: March 2026*
