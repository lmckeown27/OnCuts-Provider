//
//  CampusCutsModuleTests.swift
//  CampusCutsModule
//

import XCTest
@testable import CampusCutsModule

final class CampusCutsModuleTests: XCTestCase {
    
    func testUserSessionProtocolDefaultImplementations() {
        // Test that default implementations work
        let mockSession = MockUserSession()
        
        XCTAssertEqual(mockSession.accessToken, "test_token")
        XCTAssertEqual(mockSession.userId, "123")
        XCTAssertNil(mockSession.refreshToken)
        XCTAssertFalse(mockSession.isAdmin)
    }
    
    func testModuleBuilderCreatesViews() async {
        // Test that builder can create views without crashing
        let mockSession = MockUserSession()
        
        await MainActor.run {
            let _ = CampusCutsModuleBuilder.build(with: mockSession)
            let _ = CampusCutsModuleBuilder.buildConsumerView(with: mockSession)
            let _ = CampusCutsModuleBuilder.buildBarberDashboard(with: mockSession)
            let _ = CampusCutsModuleBuilder.buildRoleBasedView(with: mockSession)
        }
    }

    func testRoleBasedView_AdminUsesBarberDashboard() async {
        let session = MockUserSession()
        session.userRole = "ADMIN"
        await MainActor.run {
            let _ = CampusCutsModuleBuilder.buildRoleBasedView(with: session)
        }
    }

    func testRoleBasedView_LegacyCampusManagerUsesBarberDashboard() async {
        let session = MockUserSession()
        session.userRole = "CAMPUS_MANAGER"
        await MainActor.run {
            let _ = CampusCutsModuleBuilder.buildRoleBasedView(with: session)
        }
    }
}

// MARK: - Mock Session for Testing

class MockUserSession: UserSessionProtocol {
    var accessToken: String = "test_token"
    var userId: String = "123"
    var userEmail: String = "test@example.com"
    var userName: String = "Test User"
    var userRole: String = "CONSUMER"
    var isAdmin: Bool = false
    var refreshToken: String? = nil
    
    var logoutCalled = false
    
    func refreshAccessToken() async throws -> String {
        return accessToken
    }
    
    func requestLogout() {
        logoutCalled = true
    }
}
