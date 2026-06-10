//
//  CampusCutsClient.swift
//  CampusCutsModule
//
//  Host-facing configuration for environment, production safety mode, and module entry.
//

import SwiftUI

/// Shared configuration for the CampusCuts feature module.
public final class CampusCutsClient: @unchecked Sendable {
    public let environment: CampusCutsEnvironment
    /// When `true`, the shell should show a live-data banner and avoid real financial actions while debugging UI.
    public let isProduction: Bool
    public let session: UserSessionProtocol

    public init(session: UserSessionProtocol, environment: CampusCutsEnvironment = .production, isProduction: Bool = false) {
        self.session = session
        self.environment = environment
        self.isProduction = isProduction
    }

    @MainActor
    public func makeHomeView() -> some View {
        CampusCutsModuleBuilder.build(with: session, client: self)
    }

    @MainActor
    public func makeBarberDashboard() -> some View {
        CampusCutsModuleBuilder.buildBarberDashboard(with: session, client: self)
    }

    @MainActor
    public func makeConsumerView() -> some View {
        CampusCutsModuleBuilder.buildConsumerView(with: session, client: self)
    }

    @MainActor
    public func makeRoleBasedView() -> some View {
        CampusCutsModuleBuilder.buildRoleBasedView(with: session, client: self)
    }
}
