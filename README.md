# OnCuts Provider

Native iOS app for **service providers** on the [OnCuts](https://oncuts.com) platform — the campus marketplace that connects students with on-site providers (haircuts and related services).

OnCuts Provider is the provider-side companion to the consumer web and iOS experiences. It targets barbers and other approved service providers who manage schedules, bookings, messaging, and payouts.

---

## Overview

| | |
|---|---|
| **Platform** | iOS (SwiftUI + UIKit) |
| **Bundle ID** | `com.oncutsprovider.app` |
| **Display name** | OnCuts Provider |
| **Backend** | `https://oncuts.com/api/v1` |
| **Web parity reference** | [oncuts.com/web/barber](https://oncuts.com/web/barber) |

The app mirrors the web provider dashboard (`BarberPage` in the shared codebase) as a native experience: schedule hub, booking requests, messaging, availability, services & pricing, Stripe Connect payouts, and business analytics.

---

## Repository structure

```
OnCuts Provider/
├── OnCuts Provider/              # iOS app (Xcode project)
│   ├── OnCuts Provider/          # Swift sources (~130 files)
│   ├── OnCuts Provider.xcodeproj
│   └── OnCutsProvider-Info.plist
└── OnCutsPackage/                # Shared platform (backend, web, modules)
    ├── backend/                  # Node.js / Express API
    ├── web-app/                  # React consumer + provider web
    ├── ios-module/               # OnCutsModule Swift package
    ├── ios-app/                  # Consumer iOS app
    └── contracts/                # Sui Move smart contracts
```

**OnCuts Provider** is the Xcode host app. It depends on **OnCutsModule** (local Swift package in `OnCutsPackage/`) for shared auth, HTTP client, and models.

---

## Features

### Core provider workflow
- **Schedule dashboard** — zoomable calendar, weekly swimlane view, day detail
- **Booking requests** — accept, decline, reschedule pending requests
- **Bookings lifecycle** — reschedule, cancel, mark complete, undo completion, awaiting-payment tracking
- **Messaging** — consumer and campus peer conversations (UIKit chat layer)
- **Availability** — weekly schedule editor, one-off time blocks, Google Calendar integration
- **Services & pricing** — campus catalog + per-service pricing
- **Profile** — display name, bio, photo, Instagram, visibility toggle

### Business & payouts
- **Stripe Connect** — onboarding, Express dashboard, payout summary
- **Business analytics** — earnings, client insights, performance timeline

### Platform integration
- **Authentication** — email/password, Apple Sign In, Google Sign In
- **Push notifications** — APNs device registration
- **Location** — background location updates for discovery
- **Real-time sync** — Socket.IO for booking and availability updates

### Elevated roles
- **Campus manager** and **admin** surfaces for privileged accounts

---

## Requirements

- **Xcode** with iOS 26.2 SDK (see `IPHONEOS_DEPLOYMENT_TARGET` in the project)
- **Apple Developer** account (for device builds, push notifications, Sign in with Apple)
- **Google OAuth** client configured for the app URL scheme (see `OnCutsProvider-Info.plist`)
- Network access to the OnCuts API (production or a local backend)

---

## Getting started

### 1. Open the project

```bash
open "OnCuts Provider/OnCuts Provider.xcodeproj"
```

### 2. Resolve Swift Package dependencies

Xcode should automatically resolve:
- **OnCutsModule** — local package at `OnCutsPackage/`
- **Stripe iOS SDK** — via Swift Package Manager

If packages fail to resolve: **File → Packages → Reset Package Caches**, then build again.

### 3. Select a target and run

- Scheme: **OnCuts Provider**
- Destination: simulator or a connected device
- **Product → Run** (⌘R)

### 4. Sign in

Use an existing provider account, or create one through the in-app registration flow. Accounts without a provider profile are routed to the enrollment/application screen.

---

## Configuration

API and socket origins are defined in `OnCuts Provider/OnCuts Provider/AppConfiguration.swift`.

| Variable | Purpose | Default |
|----------|---------|---------|
| `CAMPUSCUTS_API_BASE` | REST API base URL | `https://oncuts.com/api/v1` |
| `CAMPUSCUTS_SOCKET_ORIGIN` | Socket.IO origin | `https://oncuts.com` |

Override these in the Xcode scheme (**Edit Scheme → Run → Arguments → Environment Variables**) when pointing at a local or staging backend.

---

## Architecture

```
┌─────────────────────────────────────┐
│         OnCuts Provider (iOS)       │
│  SwiftUI shell + UIKit messaging    │
└──────────────┬──────────────────────┘
               │ OnCutsModule
┌──────────────▼──────────────────────┐
│   ProviderSession + Service layer   │
│   (ProviderBookingsService, etc.)   │
└──────────────┬──────────────────────┘
               │ REST + Socket.IO
┌──────────────▼──────────────────────┐
│     OnCutsPackage/backend           │
│     PostgreSQL · Stripe · Sui       │
└─────────────────────────────────────┘
```

### Key types

| File / type | Role |
|-------------|------|
| `OnCutsProviderApp` | App entry, session bootstrap |
| `RootView` | Auth gate → enrollment → provider shell |
| `ProviderSession` | JWT session, profile sync, sign-in/out |
| `ProviderDashboardShellView` | Main hub (header + schedule) |
| `ProviderShellRoute` | Deep links: messages, account, services, availability, payouts, admin |
| `AppConfiguration` | API base URLs and OAuth endpoints |

### Service layer

Provider-specific API clients live under `OnCuts Provider/OnCuts Provider/Services/`:

- `ProviderAuthService` — login, session, profile
- `ProviderBookingsService` — confirmed bookings
- `ProviderBookingRequestsService` — pending requests
- `ProviderMessagesService` — conversations
- `ProviderAvailabilityService` — schedule and time blocks
- `ProviderBarberPayoutService` — Stripe Connect
- `ProviderBarberAnalyticsService` — business analytics

---

## Terminology

Product copy in OnCuts Provider uses **service provider**. The backend and shared web codebase still use **barber** in many API paths, database tables, and legacy component names (`/barbers/...`, `BarberPage`, `role=barber`). The iOS app calls those endpoints as-is.

---

## OnCutsPackage (shared platform)

The `OnCutsPackage/` directory contains the full OnCuts stack. You typically do not need to run it locally to develop the provider app, but it is useful for backend changes or web parity work.

| Component | Docs | Quick start |
|-----------|------|-------------|
| Backend | [OnCutsPackage/README.md](OnCutsPackage/README.md) | `cd OnCutsPackage/backend && npm install && npm run dev` |
| Web app | [OnCutsPackage/PAGE_FLOWS.md](OnCutsPackage/PAGE_FLOWS.md) | `cd OnCutsPackage/web-app && npm install && npm run dev` |
| iOS module | [OnCutsPackage/ios-module/README.md](OnCutsPackage/ios-module/README.md) | Local Swift package consumed by this app |

---

## Testing

```bash
# Unit tests (Xcode)
⌘U

# Or from the command line
xcodebuild test \
  -project "OnCuts Provider/OnCuts Provider.xcodeproj" \
  -scheme "OnCuts Provider" \
  -destination "platform=iOS Simulator,name=iPhone 16"
```

Test targets: **OnCuts ProviderTests**, **OnCuts ProviderUITests**.

---

## License

See [LICENSE](LICENSE).
