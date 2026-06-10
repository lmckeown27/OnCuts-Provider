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
}

// MARK: - Mock Session for Testing

class MockUserSession: UserSessionProtocol {
    var accessToken: String = "test_token"
    var userId: String = "123"
    var userEmail: String = "test@example.com"
    var userName: String = "Test User"
    var userRole: String = "CONSUMER"
    var refreshToken: String? = nil
    
    var logoutCalled = false
    
    func refreshAccessToken() async throws -> String {
        return accessToken
    }
    
    func requestLogout() {
        logoutCalled = true
    }
}

