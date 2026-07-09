# CampusCuts iOS Module

A Swift Package feature module for the CampusCuts platform, designed to be pulled into a Shell app using a **Contract-First** architecture.

## 🏗️ Architecture

This module follows a **Shell & Feature** pattern:
- The **Shell App** handles authentication and provides a `UserSessionProtocol` conforming object
- This **Feature Module** receives the session and builds its own views/networking

```
ios-module/
├── Package.swift                    # Swift Package manifest
├── README.md
├── Sources/
│   └── OnCutsModule/
│       ├── OnCutsModuleBuilder.swift    # Public entry factory
│       ├── Protocols/
│       │   └── UserSessionProtocol.swift    # Public contract
│       ├── Views/                           # Internal SwiftUI views
│       ├── ViewModels/                      # Internal @Observable view models
│       ├── Services/                        # Internal API networking
│       ├── Models/                          # Internal data models
│       └── Resources/                       # Module-specific assets
└── Tests/
    └── OnCutsModuleTests/
```

## 📦 Installation

### Add to Shell App via Xcode

1. In Xcode: **File > Add Package Dependencies...**
2. Enter your repository URL (or use local path during development)
3. Select version/branch
4. Add `OnCutsModule` to your target

### Or via Package.swift

```swift
dependencies: [
    .package(url: "https://github.com/your-org/CampusCuts.git", from: "1.0.0")
    // Or for subdirectory:
    .package(path: "../CampusCuts/ios-module")
]
```

## 🔌 Integration

### 1. Conform to UserSessionProtocol

In your Shell app, make your session manager conform to the protocol:

```swift
import OnCutsModule

class ShellUserSession: UserSessionProtocol {
    var accessToken: String { authManager.currentToken }
    var userId: String { authManager.userId }
    var userEmail: String { authManager.userEmail }
    var userName: String { authManager.displayName }
    var userRole: String { authManager.role }  // "CONSUMER", "BARBER", "CAMPUS_MANAGER", "ADMIN"
    
    func refreshAccessToken() async throws -> String {
        return try await authManager.refreshToken()
    }
    
    func requestLogout() {
        authManager.logout()
        // Navigate to login screen
    }
}
```

### 2. Build the Module View

Use the `OnCutsModuleBuilder` to get the entry view:

```swift
import SwiftUI
import OnCutsModule

struct ContentView: View {
    @StateObject var session = ShellUserSession()
    
    var body: some View {
        // Option A: Let the module decide based on user role
        OnCutsModuleBuilder.buildRoleBasedView(with: session)
        
        // Option B: Explicitly choose the view
        // OnCutsModuleBuilder.buildConsumerView(with: session)
        // OnCutsModuleBuilder.buildBarberDashboard(with: session)
    }
}
```

### 3. Navigate from Your Feature Grid

```swift
// In your Shell app's service selection
NavigationLink(destination: OnCutsModuleBuilder.build(with: session)) {
    ServiceTile(
        icon: "scissors",
        title: "CampusCuts",
        subtitle: "Campus haircuts"
    )
}
```

## 🔐 Public vs Internal

| Access Level | Components |
|--------------|------------|
| **Public** | `OnCutsModuleBuilder`, `UserSessionProtocol` |
| **Internal** | Views, ViewModels, APIService, Models |

The Shell app only needs to interact with the Builder and Protocol. All internal implementation is hidden.

## 🌐 API Configuration

The module connects to the CampusCuts backend API at `https://api.campuscut.com/api/v1`. It uses the injected `accessToken` for all authenticated requests.

### Supported Endpoints

- `/barbers` - List barbers
- `/barbers/{id}/availability` - Get availability
- `/bookings` - CRUD operations
- `/messages` - Booking messages
- `/campuses` - List campuses
- `/reviews` - Submit/fetch reviews

## 🎨 Customization

### Colors & Branding

The module uses system colors by default. To customize:

1. Add your brand colors to `Resources/Colors.xcassets`
2. Update views to use custom color assets

### Extending the Module

To add new features:

1. Add new internal Views/ViewModels
2. Expose new builder methods if needed for Shell navigation
3. Keep networking internal to this module

## 🧪 Testing

```bash
swift test
```

Run tests to verify protocol conformance and view creation.

## 📋 Requirements

- iOS 15.0+
- Swift 5.9+
- Xcode 15.0+

## 🔗 Related

- [CampusCuts Web App](../web-app) - React/Vite frontend
- [CampusCuts Backend](../backend) - Node.js/Express API
- [API Documentation](../docs/api)

