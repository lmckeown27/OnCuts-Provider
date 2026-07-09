# CampusCuts iOS Design System

> A comprehensive guide for building the native iOS frontend based on the CampusCuts web platform.

---

## Table of Contents

1. [Brand Identity](#brand-identity)
2. [Color System](#color-system)
3. [Typography](#typography)
4. [Iconography](#iconography)
5. [Spacing & Layout](#spacing--layout)
6. [Component Library](#component-library)
7. [User Flows](#user-flows)
8. [Screen Specifications](#screen-specifications)
9. [Animation Guidelines](#animation-guidelines)
10. [Accessibility](#accessibility)

---

## Brand Identity

### Brand Name
**CampusCuts** (also referenced as CampusCut or CampusKinect in some branding)

### Brand Positioning
CampusCuts is a peer-to-peer campus haircut marketplace connecting student barbers with customers. The platform emphasizes:
- **Convenience**: Mobile-first, on-campus service
- **Trust**: Reviews, Instagram portfolios, verified students
- **Affordability**: Lower fees than traditional barbershops (15% platform fee vs 40-60%)
- **Community**: Campus-based network

### Logo
- Primary logo: Chair icon with "CampusCuts" wordmark
- App icon: Stylized barber chair in olive green

---

## Color System

### Primary Palette - Olive Green

The signature color is a sophisticated olive green that conveys trust and professionalism.

```swift
extension Color {
    // Primary Olive Green Scale
    static let primary50 = Color(hex: "F2F5F4")   // Lightest - backgrounds
    static let primary100 = Color(hex: "E6EBEA")  // Light - hover states
    static let primary200 = Color(hex: "BFCDC8")  // Light accent
    static let primary300 = Color(hex: "99AFA7")  // Medium light
    static let primary400 = Color(hex: "708D81")  // DEFAULT - main brand color
    static let primary500 = Color(hex: "5A7268")  // Medium dark - buttons
    static let primary600 = Color(hex: "445750")  // Dark - button hover
    static let primary700 = Color(hex: "2E3C38")  // Darker
    static let primary800 = Color(hex: "172120")  // Near black
    static let primary900 = Color(hex: "0B1110")  // Darkest
}
```

### Neutral Grays

```swift
extension Color {
    static let neutral50 = Color(hex: "FAFAFA")   // Page background
    static let neutral100 = Color(hex: "F5F5F5")  // Card backgrounds
    static let neutral200 = Color(hex: "E5E5E5")  // Borders
    static let neutral300 = Color(hex: "D4D4D4")  // Disabled
    static let neutral400 = Color(hex: "A3A3A3")  // Placeholder text
    static let neutral500 = Color(hex: "737373")  // Secondary text
    static let neutral600 = Color(hex: "525252")  // Body text
    static let neutral700 = Color(hex: "404040")  // Headings
    static let neutral800 = Color(hex: "262626")  // Dark text
    static let neutral900 = Color(hex: "171717")  // Near black
}
```

### Semantic Colors

```swift
extension Color {
    static let success = Color(hex: "22C55E")    // Green - confirmations
    static let warning = Color(hex: "F59E0B")    // Amber - warnings
    static let error = Color(hex: "EF4444")      // Red - errors, destructive
    static let info = Color(hex: "3B82F6")       // Blue - informational
}
```

### Status Colors (Bookings)

| Status | Color | Hex | Usage |
|--------|-------|-----|-------|
| Pending | Orange | `#F59E0B` | Awaiting barber response |
| Accepted/Confirmed | Blue | `#3B82F6` | Booking confirmed |
| Completed | Green | `#22C55E` | Service finished |
| Cancelled | Red | `#EF4444` | Booking cancelled |
| Rejected | Red | `#EF4444` | Barber declined |
| No Show | Gray | `#6B7280` | Customer didn't appear |

---

## Typography

### Font Family
**Source Serif 4** - A modern serif font that adds sophistication and readability.

For iOS, use the closest system alternative or embed the font:
- **Primary**: Source Serif 4 (embedded)
- **Fallback**: Georgia, Times New Roman, or SF Pro (system)

### Type Scale

```swift
extension Font {
    // Headings
    static let displayLarge = Font.custom("SourceSerif4-Bold", size: 36)
    static let displayMedium = Font.custom("SourceSerif4-Bold", size: 30)
    static let displaySmall = Font.custom("SourceSerif4-SemiBold", size: 24)
    
    static let headlineLarge = Font.custom("SourceSerif4-SemiBold", size: 22)
    static let headlineMedium = Font.custom("SourceSerif4-SemiBold", size: 20)
    static let headlineSmall = Font.custom("SourceSerif4-SemiBold", size: 18)
    
    // Body
    static let bodyLarge = Font.custom("SourceSerif4-Medium", size: 16)
    static let bodyMedium = Font.custom("SourceSerif4-Regular", size: 14)
    static let bodySmall = Font.custom("SourceSerif4-Regular", size: 12)
    
    // Labels
    static let labelLarge = Font.custom("SourceSerif4-Medium", size: 14)
    static let labelMedium = Font.custom("SourceSerif4-Medium", size: 12)
    static let labelSmall = Font.custom("SourceSerif4-Medium", size: 10)
    
    // Captions
    static let caption = Font.custom("SourceSerif4-Regular", size: 12)
    static let captionSmall = Font.custom("SourceSerif4-Regular", size: 10)
}
```

### Font Weights
- **Regular (400)**: Body text, descriptions
- **Medium (500)**: Default weight, labels, buttons
- **SemiBold (600)**: Subheadings, emphasis
- **Bold (700)**: Headlines, important text

---

## Iconography

### Icon Library
Use **Lucide Icons** (React) or **SF Symbols** (iOS) for consistency.

### Core Icons Mapping

| Function | Lucide (Web) | SF Symbol (iOS) |
|----------|--------------|-----------------|
| User/Profile | `User` | `person.circle.fill` |
| Calendar | `Calendar` | `calendar` |
| Scissors | `Scissors` | `scissors` |
| Settings | `Settings` | `gearshape.fill` |
| Messages | `MessageCircle` | `message.fill` |
| Notifications | `Bell` | `bell.fill` |
| Location | `MapPin` | `mappin.circle.fill` |
| Search | `Search` | `magnifyingglass` |
| Star/Rating | `Star` | `star.fill` |
| Money/Price | `DollarSign` | `dollarsign.circle.fill` |
| Clock/Time | `Clock` | `clock.fill` |
| Check/Success | `Check` | `checkmark.circle.fill` |
| Close/Cancel | `X` | `xmark.circle.fill` |
| Arrow Back | `ArrowLeft` | `chevron.left` |
| Arrow Right | `ChevronRight` | `chevron.right` |
| Menu | `Menu` | `line.3.horizontal` |
| Instagram | `Instagram` | Custom or SF Symbol |
| Logout | `LogOut` | `rectangle.portrait.and.arrow.right` |

---

## Spacing & Layout

### Spacing Scale (8pt Grid)

```swift
extension CGFloat {
    static let space0 = 0.0
    static let space1 = 4.0      // Tight spacing
    static let space2 = 8.0      // Default small
    static let space3 = 12.0     // Medium small
    static let space4 = 16.0     // Default medium
    static let space5 = 20.0     // Medium
    static let space6 = 24.0     // Large
    static let space8 = 32.0     // Extra large
    static let space10 = 40.0    // Section spacing
    static let space12 = 48.0    // Large section
    static let space16 = 64.0    // Page margins
}
```

### Corner Radius

```swift
extension CGFloat {
    static let radiusSmall = 4.0     // Tags, badges
    static let radiusMedium = 8.0    // Buttons, inputs
    static let radiusLarge = 12.0    // Cards
    static let radiusXL = 16.0       // Large cards, modals
    static let radiusFull = 9999.0   // Pills, avatars (Capsule)
}
```

### Safe Areas
Always respect iOS safe areas:
- Top: Status bar + notch
- Bottom: Home indicator

---

## Component Library

### 1. Buttons

#### Primary Button
```swift
struct PrimaryButton: View {
    let title: String
    let action: () -> Void
    var isLoading: Bool = false
    var isDisabled: Bool = false
    
    var body: some View {
        Button(action: action) {
            HStack {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(title)
                    .font(.custom("SourceSerif4-Medium", size: 16))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(isDisabled ? Color.neutral300 : Color.primary500)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .disabled(isDisabled || isLoading)
    }
}
```

#### Button Variants
| Variant | Background | Text | Border |
|---------|------------|------|--------|
| Primary | `primary600` | White | None |
| Secondary | `gray200` | `gray900` | None |
| Outline | Transparent | `primary600` | `primary600` |
| Danger | `red600` | White | None |
| Ghost | Transparent | `primary600` | None |

#### Button Sizes
| Size | Padding (H/V) | Font Size |
|------|---------------|-----------|
| Small | 12/6 | 14 |
| Medium | 16/10 | 16 |
| Large | 24/14 | 18 |

### 2. Cards

```swift
struct CampusCutsCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = 16
    var cornerRadius: CGFloat = 16
    var shadowRadius: CGFloat = 8
    
    var body: some View {
        content
            .padding(padding)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .shadow(color: .black.opacity(0.05), radius: shadowRadius, x: 0, y: 2)
    }
}
```

### 3. Barber Card

The barber card is a key component showing:
- Profile image (64x64, circular)
- Business name (headline)
- Bio snippet (2 lines max)
- Rating (star icon + number)
- Completed cuts count
- Available now indicator (green dot)
- Chevron for navigation

```swift
struct BarberCard: View {
    let barber: Barber
    
    var body: some View {
        HStack(spacing: 16) {
            // Profile Image
            AsyncImage(url: barber.profileImageUrl) { image in
                image.resizable().aspectRatio(contentMode: .fill)
            } placeholder: {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 64, height: 64)
            .clipShape(Circle())
            
            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(barber.businessName)
                    .font(.headline)
                
                if let bio = barber.bio {
                    Text(bio)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                HStack(spacing: 12) {
                    if let rating = barber.rating {
                        Label(String(format: "%.1f", rating), systemImage: "star.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    
                    if let count = barber.completedBookings {
                        Text("\(count) \(count == 1 ? "cut" : "cuts")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            Spacer()
            
            // Available indicator
            if barber.isAvailableNow {
                Circle()
                    .fill(.green)
                    .frame(width: 10, height: 10)
            }
            
            Image(systemName: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.05), radius: 8, x: 0, y: 2)
    }
}
```

### 4. Booking Card

Shows booking details with status badge:
- Barber image + name
- Service name
- Date and time
- Price
- Status badge (color-coded)
- Action buttons (Cancel, etc.)

### 5. Status Badge

```swift
struct StatusBadge: View {
    let status: BookingStatus
    
    var body: some View {
        Text(status.displayName)
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.15))
            .foregroundStyle(statusColor)
            .clipShape(Capsule())
    }
    
    var statusColor: Color {
        switch status {
        case .pending: return .orange
        case .accepted, .confirmed: return .blue
        case .completed: return .green
        case .cancelled, .rejected: return .red
        case .noShow: return .gray
        }
    }
}
```

### 6. Tab Picker (Segmented Control)

Custom tab picker used for switching views (Browse/My Bookings, Pending/Upcoming/Past):

```swift
struct TabPicker<T: Hashable>: View {
    let tabs: [T]
    @Binding var selectedTab: T
    let titleFor: (T) -> String
    let badgeFor: ((T) -> Int?)?
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs, id: \.self) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 4) {
                            Text(titleFor(tab))
                            
                            if let badge = badgeFor?(tab), badge > 0 {
                                Text("\(badge)")
                                    .font(.caption2)
                                    .fontWeight(.bold)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.accentColor)
                                    .foregroundStyle(.white)
                                    .clipShape(Capsule())
                            }
                        }
                        .font(.subheadline)
                        .fontWeight(selectedTab == tab ? .semibold : .regular)
                        .foregroundStyle(selectedTab == tab ? .primary : .secondary)
                        
                        Rectangle()
                            .fill(selectedTab == tab ? Color.accentColor : .clear)
                            .frame(height: 2)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
```

### 7. Search Bar

```swift
struct SearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search..."
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(placeholder, text: $text)
        }
        .padding(12)
        .background(Color.platformGray6)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
```

### 8. Avatar

```swift
struct AvatarView: View {
    let imageUrl: String?
    let name: String
    var size: CGFloat = 48
    
    var body: some View {
        Group {
            if let url = imageUrl, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { image in
                    image.resizable().aspectRatio(contentMode: .fill)
                } placeholder: {
                    initialsView
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
    
    var initialsView: some View {
        ZStack {
            Color.gray.opacity(0.3)
            Text(initials)
                .font(.system(size: size * 0.4, weight: .bold))
                .foregroundStyle(.gray)
        }
    }
    
    var initials: String {
        let parts = name.split(separator: " ")
        let first = parts.first?.prefix(1) ?? ""
        let last = parts.count > 1 ? parts.last?.prefix(1) ?? "" : ""
        return "\(first)\(last)".uppercased()
    }
}
```

---

## User Flows

### Consumer Flow

```
Landing Page
    ↓
Select University → Consumer Home
    ↓
Browse Barbers → View Barber Profile → Instagram Portfolio
    ↓
Select Service → Pick Date/Time → Choose Location
    ↓
Submit Booking Request
    ↓
[Barber Accepts/Declines]
    ↓
[Service Completed]
    ↓
Payment (Card/Apple Pay) + Tip
    ↓
Leave Review
```

### Barber Flow

```
Auth → Barber Dashboard
    ↓
├── View Pending Requests → Accept/Decline
├── View Upcoming Appointments → Mark Complete
├── View Past Bookings
├── Edit Profile (Bio, Photo, Instagram)
├── Manage Services (Add/Edit/Price)
├── Set Availability (Weekly Schedule)
├── Manage Locations
├── View Earnings & Payouts
├── Connect Stripe
├── Messages
└── Notifications
```

### Key Screens

| Screen | Consumer | Barber |
|--------|----------|--------|
| Home/Dashboard | Browse barbers | Booking calendar |
| Profile | Edit personal info | Edit business profile |
| Bookings | My bookings | Pending/Upcoming/Past |
| Messages | Chat with barber | Chat with customers |
| Payments | Payment history | Earnings & payouts |
| Settings | Account settings | Account + business |

---

## Screen Specifications

### Consumer Home Screen

**Header:**
- Navigation title: "CampusCuts"
- Profile button (right) - opens dropdown menu

**Tab Picker:**
- "Browse" | "My Bookings"
- Badge on "My Bookings" showing upcoming count

**Browse Tab:**
- Search bar at top
- Vertical scrolling list of Barber Cards
- Pull-to-refresh

**My Bookings Tab:**
- Sections: "Upcoming" and "Past"
- Each booking shows: barber info, service, date/time, status, price
- Cancel button for pending/accepted bookings

### Barber Dashboard Screen

**Header:**
- Navigation title: "Dashboard"
- Profile button (right)

**Tab Picker:**
- "Pending" | "Upcoming" | "Past"
- Badge on "Pending" showing request count

**Calendar View:**
- Date picker/navigator
- Daily/Weekly/Monthly toggle
- Shows appointments as time blocks

**Booking Cards:**
- Customer name
- Service + price
- Date/time
- Accept/Decline buttons (pending)
- Mark Complete button (upcoming)

### Profile Dropdown Menu

Items:
- View Profile
- Edit Profile
- Become a Barber (consumers only)
- Messages
- Settings
- Privacy Policy
- Terms of Service
- Logout (destructive)

---

## Animation Guidelines

### Transitions

| Action | Animation | Duration |
|--------|-----------|----------|
| Modal appear | Slide up from bottom | 300ms |
| Modal dismiss | Slide down | 200ms |
| Tab switch | Cross-fade | 200ms |
| Card tap | Scale 0.98 → 1.0 | 100ms |
| Loading | Spinner rotation | Continuous |
| Pull-to-refresh | Native | System |

### Easing Curves
- **Appear**: `easeOut` or `spring(response: 0.3, dampingFraction: 0.7)`
- **Dismiss**: `easeIn`
- **Interactive**: `interactiveSpring()`

### Animation Code Examples

```swift
// Modal slide-up animation
.transition(.move(edge: .bottom))
.animation(.easeOut(duration: 0.3), value: isPresented)

// Card press feedback
.scaleEffect(isPressed ? 0.98 : 1.0)
.animation(.easeInOut(duration: 0.1), value: isPressed)

// Fade in
.opacity(isVisible ? 1 : 0)
.animation(.easeIn(duration: 0.2), value: isVisible)
```

---

## Accessibility

### VoiceOver Support
- All interactive elements must have accessibility labels
- Images need descriptive accessibility labels
- Status badges should announce status
- Form fields need proper labels

### Dynamic Type
- Support Dynamic Type scaling
- Test with accessibility font sizes
- Ensure text doesn't truncate critically

### Color Contrast
- Maintain 4.5:1 contrast ratio for text
- Don't rely solely on color for status (use icons too)

### Touch Targets
- Minimum 44x44pt touch targets
- Adequate spacing between interactive elements

### Reduced Motion
- Respect `UIAccessibility.isReduceMotionEnabled`
- Provide alternative non-animated transitions

---

## Implementation Notes

### API Base URL
```swift
let apiBaseURL = "https://api.campuscut.com/api/v1"
```

### Authentication
- JWT token-based auth
- Token stored in Keychain
- Refresh token flow for expired tokens

### Real-time Features
- WebSocket connection for messages
- Push notifications for bookings

### Image Handling
- Profile images: 200x200 recommended
- Portfolio images: 800x600 recommended
- Use AsyncImage with placeholder
- Implement image caching

### Date/Time Handling
- All times stored as UTC on backend
- Display in user's local timezone
- Format: "Mar 10, 2026 at 2:00 PM"

---

## Appendix: Color Hex Reference

```
Primary Olive:
  50: #F2F5F4   100: #E6EBEA   200: #BFCDC8   300: #99AFA7
  400: #708D81   500: #5A7268   600: #445750   700: #2E3C38
  800: #172120   900: #0B1110

Neutral Gray:
  50: #FAFAFA   100: #F5F5F5   200: #E5E5E5   300: #D4D4D4
  400: #A3A3A3   500: #737373   600: #525252   700: #404040
  800: #262626   900: #171717

Semantic:
  Success: #22C55E   Warning: #F59E0B   Error: #EF4444   Info: #3B82F6
```

---

*Last updated: March 2026*
*Version: 1.0*

