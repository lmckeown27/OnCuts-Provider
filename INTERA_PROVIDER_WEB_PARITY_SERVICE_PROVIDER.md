# Intera Provider app — service provider capabilities from CampusCuts (web)

This document inventories **what a service provider can do today** on the CampusCuts web experience (`/web/*`), grouped by product area. Use it as a **parity checklist** when building the Intera Provider app.

**Terminology**

- **Service provider** — The person or business offering on-site services (hair, nails, etc.). CampusCuts and this codebase still use **“barber”** in many **URLs, tables, and React names** (`/web/barber`, `BarberPage`, `/barbers/...`). Those literals are kept below for implementation accuracy; product copy in Intera Provider should prefer **service provider** unless you are citing code or the API.

**Scope notes**

- The **primary service provider hub** on web is **`/web/barber`** (`BarberPage` — legacy component name). Most day-to-day actions live there (modals, calendar, bookings, notifications, payout settings, etc.).
- API paths below are shown **relative to the web app’s configured API base** (typically something like `/api/v1` for `api.service` calls; some older `fetch` calls use `/api/...` directly—mirror whatever the production web client uses).
- A few routes exist with **placeholder or mock UI**; they are called out so Intera is not built against non-functional web screens alone.

---

## 1. Authentication, session, and role switching

| Action | Where (web) | API / behavior |
|--------|-------------|----------------|
| Sign in / session (same as rest of app) | Auth flows outside this doc | Standard auth + JWT in storage (see `useAuthStore`). |
| **Sign out** | Service provider dashboard header / profile area | `useAuthStore.logout()`. |
| **Switch to consumer** | Service provider header / menu | Navigate to `/web/consumer` (or `/app/consumer` on app platform). |

---

## 2. Service provider dashboard hub (`/web/barber`)

Central surface: **`BarberPage`** (legacy name in repo).

| Action | UI | API / notes |
|--------|-----|-------------|
| **Open / refresh dashboard** | Landing on `/web/barber` | Loads provider profile, bookings, availability, etc. |
| **Pull to refresh** | Mobile-style refresh on dashboard | Re-fetches dashboard data. |
| **Background location** | Automatic when dashboard loads | `useGeolocation()` updates provider location for discovery (hook on `BarberPage`). |
| **Open booking requests inbox** | Inbox / pending requests UI | Uses `BarberBookingRequestsDropdown` (pending list). |
| **Open notifications** | Bell / notifications panel | `GET /notifications` (paginated); filters: all, bookings, payments, reviews, cancellations, messages. |
| **Mark one notification read** | Notification row | `PUT /notifications/:id/read`. |
| **Mark all notifications read** | Control in panel | `PUT /notifications/read-all`. |
| **Delete all notifications** | Control in panel | `DELETE /notifications/all`. |
| **Tap notification → deep link** | Various | Often navigates to `/web/barber/messages/:conversationId` or similar based on `data`. |
| **Open profile editor** | Settings / profile entry | Modal: `BarberProfileEditor`. |
| **Open services & pricing** | Service specialties modal | `BarberServiceSpecialties` — toggles offered services and prices; persists via provider profile `PUT` (`/barbers/:id`). |
| **Open campus peer chats** | Chats with other service providers on campus | `BarberChatsModal` → pick a peer → opens messaging flow (see §7). |
| **Open “my locations”** | Locations modal | `BarberLocationsModal` (see §6). |
| **Open weekly availability editor** | Availability modal | Multi-interval per day; save (see §4). |
| **Open block time** | Block time on calendar | `BlockTimeModal` — create one-off blocks (see §4). |
| **Open booking / day detail** | Calendar / booking modals | Inline booking editor, complete/cancel/reschedule (see §3). |
| **Open service / appointment detail** | Service details modal | `ServiceDetailsModal` for context on a slot/booking. |
| **Open payout settings** | Payout / Stripe entry (also `?showPayoutSettings=true`) | `PaymentManagementModal` (see §5). |
| **Open campus manager dashboard** | If user is campus manager | `CampusManagerDashboard` modal (see §12). |
| **Open admin dashboard** | If user is admin | `AdminDashboard` modal (see §12). |
| **Navigate to messages** | Messages button | `/web/barber/messages` (or `/app/barber/messages`). |
| **Start conversation from booking context** | In-flow actions | `messageService.startBookingConversation` / `POST /messages/conversations` with booking context. |

---

## 3. Bookings lifecycle (requests + simple bookings)

### 3a. Incoming **booking requests** (approve / decline)

| Action | UI | API |
|--------|-----|-----|
| List pending requests for the signed-in provider | Inbox dropdown | `GET /booking-requests/barber/:barberId/pending` — `:barberId` is the **`barbers` table row id** (legacy segment name in URL). |
| **Accept** request | Accept on a request | `POST /booking-requests/:bookingId/accept` (body includes `barberId`, optional `message`). |
| **Decline** with reason | Decline flow + reasons | `POST /booking-requests/:bookingId/reject` (body includes `barberId`, `reason`). |

### 3b. **Bookings simple** (confirmed schedule — calendar / list)

| Action | UI | API |
|--------|-----|-----|
| List my bookings as provider | Dashboard / calendar | `GET /bookings-simple?role=barber` — query value **`barber`** is backend enum for the provider side of the booking. |
| Load bookings for calendar range | Dashboard | `GET /bookings-simple` with date query params (as implemented in `BarberPage`). |
| **Reschedule** (date/time) and/or **edit location** | Inline booking editor | `PUT /bookings-simple/:id` with `scheduledTime`, `location`. |
| **Cancel** booking (optional reason) | Cancel in modal | `DELETE /bookings-simple/:id` with `{ reason }` in body. |
| **Remove** booking from schedule (completed flow) | Remove control | `DELETE /bookings-simple/:id` (no reason — “remove from schedule”). |
| **Mark complete** (sends payment path) | Complete / mark done | `PUT /bookings-simple/:id/complete` |
| **Request payment** (alternate path to payment page) | Complete / payment request | `POST /bookings-simple/:id/request-payment` then navigate to `/web/payment/:bookingId`. |
| **Undo completion** (revert to accepted) | Undo in booking modal | `PUT /bookings-simple/:id/undo-complete` |
| **Update status** (generic; exists on backend) | Not guaranteed exposed in every UI | `PUT /bookings-simple/:id/status` with `status` in `PENDING \| ACCEPTED \| REJECTED \| COMPLETED \| PAID \| CANCELLED`. **Known caveat:** authorization may not match `barbers.id` vs `users.id` — prefer dedicated routes (see backend appendix). |

### 3c. Post-service **payment page** (provider + consumer)

Route: **`/web/payment/:bookingId`** (`PostServicePaymentPage`).

| Action | Who | API / behavior |
|--------|-----|----------------|
| Service provider: **wait for payment** state | Provider view when booking completed | Poll / socket-driven UI; shows consumer payment progress. |
| Service provider: **undo completion** | “Didn’t mean to mark complete” | `PUT /bookings-simple/:bookingId/undo-complete` → often `navigate('/web/barber')`. |
| Consumer: pay with Stripe (Payment Element) | Consumer view | Stripe `confirmPayment` + booking payment APIs (see `PostServicePaymentPage` — consumer-owned but part of the same flow). |

### 3d. **Past / paid visibility** (client-only)

| Action | UI | Notes |
|--------|-----|-------|
| Hide specific **paid** bookings from Past tab / slot lists | “Hide” / eye-off style controls | Persisted in **`localStorage`** key `campuscuts_barber_hidden_paid_bookings_${barberId}` — not server state. Intera Provider should decide whether to replicate or replace with server prefs. |

### 3e. **Appointment details** route (stub)

| Route | Reality |
|-------|---------|
| `/web/barber/appointment/:appointmentId` | **`AppointmentDetailsPage`** uses **mock** data, not live API. For parity, drive from `GET /bookings-simple/:id` (or equivalent) instead of this page as-is. |

---

## 4. Availability, calendar, and time blocks

### Weekly availability

| Action | UI | API |
|--------|-----|-----|
| Load weekly schedule | Availability modal + calendar | `GET /barbers/:id/availability` (returns `weeklySchedule` / `weekly_schedule` shape used by UI). |
| **Save** weekly intervals (multi-slot per day) | Availability editor | `PUT /barbers/:id` with `{ weekly_schedule: ... }` (implemented via `fetch` to `/api/v1/barbers/:id` in modal). |

Backend also exposes: `PUT /barbers/:id/availability` with `schedule` array (`updateAvailability`) — web primarily uses **`weekly_schedule` on profile PUT** for the modal shown.

### One-off blocks (busy time)

| Action | UI | API |
|--------|-----|-----|
| List blocks in range | Block time UI / calendar | `GET /barbers/:id/time-blocks?startDate&endDate` |
| **Create** block | `BlockTimeModal` | `POST /barbers/:id/time-blocks` (`blockDate`, `startTime`, `endTime`, optional `reason`). |
| **Delete** block | Unblock control | `DELETE /barbers/:id/time-blocks/:blockId` |

### Google Calendar (busy times)

| Action | UI | API |
|--------|-----|-----|
| Check connection status | Dashboard integration strip | `GET /auth/google-calendar/status` |
| **Connect** Google Calendar | Connect button | `GET /auth/google-calendar/connect` → opens OAuth URL. |
| **Disconnect** | Disconnect | `DELETE /auth/google-calendar/disconnect` |
| Load **busy** intervals for scheduling | Used when showing conflicts | `GET` busy-times endpoint as wired in `BarberPage` (see `api.get` for `busyTimes` in dashboard code). |

---

## 5. Payouts, Stripe Connect, and earnings UI

### Payout Settings modal (`PaymentManagementModal`)

| Action | API |
|--------|-----|
| Load payout summary / estimates | `GET /barber/payout/summary` (via `fetchBarberPayoutSummary` — response wrapped as `{ success, data }` in service). |
| Load legacy / chain payout flags (if shown) | `GET /barber/payout/status` |
| Load Connect onboarding state | `GET /barber/connect/status` |
| **Start Stripe Connect onboarding** | `POST /barber/connect/create` → redirect to `onboarding_url`. |
| **Open Stripe Express / Connect dashboard** | `GET /barber/connect/dashboard` → open `dashboard_url` in new tab. |

*Note:* Payout routes use the **`/barber/...`** prefix in the API today; Intera Provider calls the same endpoints regardless of in-app terminology.

### Static / informational pages

| Route | Purpose |
|-------|---------|
| `/web/barber/earnings` | **`BarberEarningsPage`** — mostly **static copy** + link back to dashboard Payout Settings; **not** a live analytics API page. |
| `/web/barber/connect`, `/web/barber/connect/return`, `/web/barber/connect/refresh` | Redirect / explain **Stripe Connect**; return URLs land on **`/web/barber?showPayoutSettings=true`**. |

### Backend analytics (available for Intera even if web under-uses)

| Endpoint | Purpose |
|----------|---------|
| `GET /barbers/:id/earnings` | Earnings summary (owner). |
| `GET /barbers/:id/analytics` | Analytics dashboard payload (owner). |

---

## 6. Locations (campus-approved cuts)

`BarberLocationsModal` — provider-facing location management (legacy component name).

| Action | API (as called from web) |
|--------|--------------------------|
| Load assigned, pending, and available locations | `GET /api/locations/my-locations` (note: path may differ from `/api/v1` prefix). |
| **Assign** self to an available campus location | `POST /api/locations/barber/assign` |
| **Unassign** from a location | `DELETE` / `POST` style per implementation: `fetch('/api/locations/barber/unassign/:locationId')` |
| **Request** a new custom location | `POST /api/locations/barber/request` |

---

## 7. Messaging (consumers + campus peers)

Routes: **`/web/barber/messages`**, **`/web/barber/messages/:conversationId`** (`MessagesPage`).

| Action | API |
|--------|-----|
| List conversations | `GET /messages/conversations?page&limit` |
| Get one conversation | `GET /messages/conversations/:id` |
| **Create** conversation (generic) | `POST /messages/conversations` |
| **Start booking-centric conversation** | Same `POST` with booking context fields (`booking_id`, `service_name`, etc.). |
| List messages | `GET /messages/conversations/:conversationId/messages?page&limit` |
| **Send** text (optional image URL) | `POST /messages/conversations/:conversationId/messages` |
| **Mark conversation read** | `PUT /messages/conversations/:conversationId/read` |
| **Delete** conversation | `DELETE /messages/conversations/:conversationId` |
| **Unread count** (header badge) | `GET /messages/unread-count` |
| **Upload chat image** | `POST /upload/chat-image` (multipart) — used for image messages. |

**Campus manager ↔ service provider** helpers also exist on `messageService` (`/messages/cm-barber`, etc.) for users with those roles.

**Provider ↔ provider** on same campus: `BarberChatsModal` loads campus roster then reuses messaging / conversation creation patterns above.

---

## 8. Profile, services, and consumer-visible settings

`BarberProfileEditor` + `BarberServiceSpecialties`.

| Action | API |
|--------|-----|
| Load my provider profile | `GET /barbers/me` or `GET /barbers/user/:userId` / `GET /barbers/:id` depending on entry. |
| **Update** display name, bio, Instagram, specialties, visibility | `PUT /barbers/:id` with fields like `display_name`, `bio`, `instagram_handle`, `specialties`, `is_active` (hide from consumers when inactive). |
| **Upload profile photo** | `userService.uploadProfilePhoto(userId, file)` (user avatar pipeline; then provider profile may reference URL). |
| **Toggle offered services + set per-service prices** | Computes `specialties` + `pricing` array; `PUT /barbers/:id` with `{ specialties, pricing }`. |

### Portfolio images (API exists; minimal web UI)

| Endpoint | Purpose |
|----------|---------|
| `GET /barbers/:id/portfolio` | Public portfolio list. |
| `POST /barbers/:id/portfolio` | Upload image (`multipart/form-data`). |
| `DELETE /barbers/:barberId/portfolio/:imageId` | Remove image. |

The profile editor copy points students to **Instagram** as portfolio; Intera Provider may still want direct portfolio CRUD for parity with **API capability**.

### Delete provider profile

| Endpoint | Notes |
|----------|-------|
| `DELETE /barbers/:id` | Backend supports **owner** delete; **no dedicated button** was found in the provider web UI—treat as optional / settings-depth if product wants it. |

---

## 9. Reviews (read)

Service providers **see** customer feedback on completed / paid bookings in dashboard modals (stars/text). Consumers submit reviews via booking payment flow (`POST /bookings-simple/:id/review` on backend). Intera Provider should at least:

- Show **per-booking** review if returned on booking payload.
- Optionally: `GET /barbers/:barberId/reviews` for a consolidated list (used elsewhere in app ecosystem).

---

## 10. Wallet page (optional / legacy product surface)

Route: **`/web/wallet`** (`WalletPage`).

- Uses **`walletV2Service`** (balance, transactions, escrows). **Not linked from `BarberPage`** in the inventory pass; providers may still open it if the app links there.
- Decide with product whether Intera **Provider** includes this or only **Stripe Connect** surfaces (§5).

---

## 11. Realtime and background sync

`BarberPage` registers **socket** listeners (via `socketService`) for events such as:

- Booking list updates when status changes (e.g. cancelled removed, accepted added).
- Booking completed / payment-related updates.
- Availability updates (`availability-update` custom event / socket).
- Notification-driven UI refresh patterns.

Intera Provider should subscribe to the **same server events** (or push equivalents) for parity with live dashboards.

---

## 12. Elevated roles on the same account

If `user.is_admin` or campus manager flags are set, **`BarberPage`** exposes extra modals:

| Surface | Purpose |
|---------|---------|
| `AdminDashboard` | Cross-campus / admin operations (uses admin API patterns — see component). |
| `CampusManagerDashboard` | Approve providers, locations, campus ops (large modal). |

These are **not** “every service provider” but **are** actions some provider accounts can take from the same web session—include in Intera if the same users install the Provider app.

---

## 13. Routes present but weak / mock (Intera caution)

| Item | Issue |
|------|-------|
| `/web/barber/service-history` | **`BarberServiceHistoryPage`** — **mock data**, not wired to API. |
| `/web/student/barbers/:barberId` / `/web/barbers/:barberId` | **`BarberProfilePage`** — placeholder “coming soon”. |
| `BarberDashboardPage` / `BarberCalendarPage` under `src/pages/barber/` | **Not mounted** in `App.tsx` routes at time of writing; legacy / unused entry points. |
| `BarberHeader` “Bookings” menu | Navigates to **`/web/barber/bookings`** — **no matching route** in `App.tsx`; likely dead link unless added later. |

---

## 14. Quick API map (provider-centric; legacy path segments)

REST paths below reflect **current CampusCuts** naming (`barbers`, `barber`, `role=barber`). Intera Provider should call them as-is until the backend offers aliases.

**Bookings**

- `GET /bookings-simple`, `GET /bookings-simple/:id`
- `PUT /bookings-simple/:id`, `DELETE /bookings-simple/:id`
- `PUT /bookings-simple/:id/complete`, `PUT /bookings-simple/:id/undo-complete`
- `POST /bookings-simple/:id/request-payment`
- `PUT /bookings-simple/:id/status`
- Plus Stripe payment-intent routes on same router for consumer checkout.

**Booking requests**

- `GET /booking-requests/barber/:barberId/pending`
- `POST /booking-requests/:bookingId/accept`, `.../reject`

**Provider profile** (`/barbers/...`)

- `GET /barbers/me`, `GET /barbers/:id`, `GET /barbers/user/:userId`
- `POST /barbers`, `PUT /barbers/:id`, `DELETE /barbers/:id`
- `GET/POST/DELETE` portfolio under `/barbers/.../portfolio`
- `GET/PUT /barbers/:id/availability`
- `GET/POST/DELETE /barbers/:id/time-blocks` (+ `DELETE .../:blockId`)
- `GET /barbers/:id/earnings`, `GET /barbers/:id/analytics`
- `GET /barbers/available-at-time` (public; rebooking helper)

**Payouts / Connect**

- `GET /barber/payout/status`, `GET /barber/payout/summary`
- `GET /barber/connect/status`, `POST /barber/connect/create`, `GET /barber/connect/dashboard`

**Messages / notifications**

- `/messages/*` as in §7
- `/notifications` and read/delete variants as in §2

**Google Calendar**

- `/auth/google-calendar/status`, `connect`, `disconnect`

---

## 15. Suggested Intera Provider parity checklist (high level)

Use this as a binary checklist per feature group:

1. **Session**: login, logout, switch-to-consumer (if product keeps one app).
2. **Dashboard**: bookings + calendar + pull-to-refresh + geolocation update policy.
3. **Requests**: pending list, accept, reject with reason.
4. **Bookings**: list/filter by date, reschedule, edit location, cancel, mark complete, undo complete, request payment, remove from schedule, hide-paid local preference (or redesign).
5. **Payments**: provider waiting screen + undo; deep link consumer to payment (handled by consumer app / web).
6. **Availability**: weekly editor + time blocks + optional Google Calendar connect.
7. **Locations**: list, assign, unassign, request new.
8. **Profile**: name, bio, photo, Instagram, specialties, offered services + prices, hide profile (`is_active`).
9. **Portfolio** (optional): upload/delete gallery (API-ready).
10. **Messaging**: conversations, send/receive, read receipts, images, unread badge, booking context headers.
11. **Notifications**: list, filters, mark read, mark all read, delete all, tap-through actions.
12. **Payouts**: Connect status, onboarding, Stripe dashboard, payout summary copy + numbers.
13. **Sockets**: booking + availability + payment lifecycle updates.
14. **Elevated roles**: campus manager + admin surfaces if same users exist.

When in doubt, treat **`BarberPage` + `MessagesPage` + `PostServicePaymentPage` + `PaymentManagementModal` + `BarberLocationsModal`** as the **source of truth** for implemented web behavior; use **`booking-simple.routes.ts`** and **`barber.routes.ts`** for **complete server capability**.
