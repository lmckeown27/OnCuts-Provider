//
//  CampusCutsLiveDataModeBanner.swift
//  CampusCutsModule
//

import SwiftUI

/// Banner shown when `CampusCutsClient.isProduction` is enabled.
public struct CampusCutsLiveDataModeBanner: View {
    public init() {}

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.subheadline.weight(.semibold))
            Text("Live Data Mode")
                .font(.subheadline.weight(.semibold))
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.orange.gradient)
    }
}
