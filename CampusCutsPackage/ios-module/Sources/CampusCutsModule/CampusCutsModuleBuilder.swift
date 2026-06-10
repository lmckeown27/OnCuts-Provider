//
//  CampusCutsModuleBuilder.swift
//  CampusCutsModule
//
//  Public entry point for the Shell app to instantiate this module.
//

import SwiftUI

/// Factory class for building the CampusCuts module views
public struct CampusCutsModuleBuilder {

    @MainActor
    public static func build(with session: UserSessionProtocol, client: CampusCutsClient) -> some View {
        let apiService = CampusCutsAPIService(session: session, environment: client.environment)
        let viewModel = CampusCutsHomeViewModel(session: session, apiService: apiService)
        return CampusCutsHomeView(viewModel: viewModel, liveDataSafetyMode: client.isProduction)
    }

    @MainActor
    public static func buildBarberDashboard(with session: UserSessionProtocol, client: CampusCutsClient) -> some View {
        let apiService = CampusCutsAPIService(session: session, environment: client.environment)
        let viewModel = BarberDashboardViewModel(session: session, apiService: apiService, liveDataSafetyMode: client.isProduction)
        return BarberDashboardView(viewModel: viewModel, liveDataSafetyMode: client.isProduction)
    }

    @MainActor
    public static func buildConsumerView(with session: UserSessionProtocol, client: CampusCutsClient) -> some View {
        let apiService = CampusCutsAPIService(session: session, environment: client.environment)
        let viewModel = ConsumerViewModel(session: session, apiService: apiService, liveDataSafetyMode: client.isProduction)
        return ConsumerHomeView(viewModel: viewModel, liveDataSafetyMode: client.isProduction)
    }

    @MainActor
    public static func buildRoleBasedView(with session: UserSessionProtocol, client: CampusCutsClient) -> some View {
        switch session.userRole {
        case "BARBER", "CAMPUS_MANAGER", "ADMIN":
            return AnyView(buildBarberDashboard(with: session, client: client))
        default:
            return AnyView(buildConsumerView(with: session, client: client))
        }
    }

    // MARK: - Legacy convenience (no production safety / default client)

    @MainActor
    public static func build(with session: UserSessionProtocol) -> some View {
        build(with: session, client: CampusCutsClient(session: session))
    }

    @MainActor
    public static func buildBarberDashboard(with session: UserSessionProtocol) -> some View {
        buildBarberDashboard(with: session, client: CampusCutsClient(session: session))
    }

    @MainActor
    public static func buildConsumerView(with session: UserSessionProtocol) -> some View {
        buildConsumerView(with: session, client: CampusCutsClient(session: session))
    }

    @MainActor
    public static func buildRoleBasedView(with session: UserSessionProtocol) -> some View {
        buildRoleBasedView(with: session, client: CampusCutsClient(session: session))
    }
}
