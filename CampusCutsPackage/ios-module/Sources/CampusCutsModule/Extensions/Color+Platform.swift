//
//  Color+Platform.swift
//  CampusCutsModule
//
//  Cross-platform color definitions for iOS and macOS compatibility.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    /// System gray level 6 - lightest gray for backgrounds
    static var platformGray6: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGray6)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
    
    /// System gray level 5
    static var platformGray5: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemGray5)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
    
    /// System background color
    static var platformBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }
    
    /// Secondary system background color
    static var platformSecondaryBackground: Color {
        #if canImport(UIKit)
        Color(uiColor: .secondarySystemBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}

