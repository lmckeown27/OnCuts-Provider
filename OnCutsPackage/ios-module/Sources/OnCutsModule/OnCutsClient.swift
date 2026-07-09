//
//  OnCutsClient.swift
//  OnCutsModule
//
//  Host-facing configuration for environment, production safety mode, and module entry.
//

import SwiftUI

/// Shared configuration for the CampusCuts feature module.
public final class OnCutsClient: @unchecked Sendable {
    public let environment: OnCutsEnvironment
    /// When `true`, the shell should show a live-data banner and avoid real financial actions while debugging UI.
    public let isProduction: Bool
    public let session: UserSessionProtocol

    public init(session: UserSessionProtocol, environment: OnCutsEnvironment = .production, isProduction: Bool = false) {
        self.session = session
        self.environment = environment
        self.isProduction = isProduction
    }

    @MainActor
    public func makeHomeView() -> some View {
        OnCutsModuleBuilder.build(with: session, client: self)
    }

    @MainActor
    public func makeBarberDashboard() -> some View {
        OnCutsModuleBuilder.buildBarberDashboard(with: session, client: self)
    }

    @MainActor
    public func makeConsumerView() -> some View {
        OnCutsModuleBuilder.buildConsumerView(with: session, client: self)
    }

    @MainActor
    public func makeRoleBasedView() -> some View {
        OnCutsModuleBuilder.buildRoleBasedView(with: session, client: self)
    }
}
