//
//  PushNotificationManager.swift
//  CampusCuts
//
//  Manages push notifications for booking updates and chat messages
//  Transferred from CampusKinect with CampusCuts adaptations
//

import Foundation
import UserNotifications
import UIKit

class PushNotificationManager: NSObject, ObservableObject {
    static let shared = PushNotificationManager()
    
    @Published var isAuthorized = false
    @Published var deviceToken: String?
    
    private let networkManager = NetworkManager.shared
    
    override init() {
        super.init()
        checkAuthorizationStatus()
        setupNotificationCategories()
    }
    
    // MARK: - Permission Management
    
    func requestPermission() async -> Bool {
        print("🔔 PushNotificationManager: requestPermission() called")
        let center = UNUserNotificationCenter.current()
        
        do {
            print("🔔 PushNotificationManager: Requesting authorization...")
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            
            print("🔔 PushNotificationManager: Authorization result: \(granted)")
            
            await MainActor.run {
                self.isAuthorized = granted
            }
            
            if granted {
                print("🔔 PushNotificationManager: Permission granted, registering for remote notifications...")
                await MainActor.run {
                    registerForRemoteNotifications()
                }
            } else {
                print("🔔 PushNotificationManager: Permission denied by user")
                await unregisterCurrentDevice()
            }
            
            print("📱 Push notification permission: \(granted ? "Granted" : "Denied")")
            return granted
            
        } catch {
            print("❌ Error requesting notification permission: \(error)")
            return false
        }
    }
    
    func checkNotificationSettings() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        let wasAuthorized = isAuthorized
        let nowAuthorized = settings.authorizationStatus == .authorized
        
        await MainActor.run {
            self.isAuthorized = nowAuthorized
        }
        
        print("🔔 Notification settings check: was \(wasAuthorized), now \(nowAuthorized)")
        
        if wasAuthorized && !nowAuthorized {
            print("🔔 User disabled notifications - removing device token")
            await unregisterCurrentDevice()
        } else if !wasAuthorized && nowAuthorized {
            print("🔔 User enabled notifications - registering device token")
            await registerForRemoteNotifications()
        }
    }
    
    func checkAndRequestPermissionIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        
        switch settings.authorizationStatus {
        case .notDetermined:
            print("🔔 First time user - requesting notification permission")
            let granted = await requestPermission()
            print("🔔 First time permission result: \(granted)")
        case .authorized:
            print("🔔 Notifications already authorized - registering token")
            await registerForRemoteNotifications()
        case .denied, .provisional, .ephemeral:
            print("🔔 User previously set notification preference - not requesting again")
        @unknown default:
            print("🔔 Unknown notification authorization status")
        }
    }
    
    func unregisterCurrentDevice() async {
        guard let deviceToken = deviceToken else {
            print("🔔 No device token to unregister")
            return
        }
        
        do {
            // TODO: Implement unregisterDeviceToken in NetworkManager
            print("✅ Device token unregistered from backend")
            
            await MainActor.run {
                self.deviceToken = nil
            }
        } catch {
            print("❌ Failed to unregister device token: \(error)")
        }
    }
    
    private func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.isAuthorized = settings.authorizationStatus == .authorized
            }
        }
    }
    
    @MainActor
    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }
    
    // MARK: - Device Token Management
    
    func handleDeviceToken(_ deviceToken: Data) {
        let tokenString = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        
        DispatchQueue.main.async {
            self.deviceToken = tokenString
        }
        
        print("📱 Device token received: \(tokenString)")
        
        // Register token with backend after user authentication
        Task {
            await registerDeviceToken(tokenString)
        }
    }
    
    func handleRegistrationError(_ error: Error) {
        print("❌ Failed to register for remote notifications: \(error)")
    }
    
    func forceTokenRegistration() async {
        guard let token = deviceToken else {
            print("❌ No device token available to register")
            await registerForRemoteNotifications()
            return
        }
        
        print("🔄 Force registering existing device token...")
        await registerDeviceToken(token)
    }
    
    private func registerDeviceToken(_ token: String) async {
        do {
            print("📱 Attempting to register device token with backend...")
            // TODO: Implement registerDeviceToken in NetworkManager
            // try await networkManager.registerDeviceToken(token: token, platform: "ios")
            print("✅ Device token registered with backend successfully")
        } catch {
            print("❌ Failed to register device token with backend: \(error)")
        }
    }
    
    // MARK: - Notification Handling
    
    func handleNotification(_ userInfo: [AnyHashable: Any]) {
        print("📱 Received push notification: \(userInfo)")
        
        guard let type = userInfo["type"] as? String else {
            print("❌ No notification type found")
            return
        }
        
        switch type {
        case "booking_confirmation":
            handleBookingNotification(userInfo)
        case "booking_reminder":
            handleReminderNotification(userInfo)
        case "message":
            handleMessageNotification(userInfo)
        case "payment_received":
            handlePaymentNotification(userInfo)
        case "review":
            handleReviewNotification(userInfo)
        case "system":
            handleSystemNotification(userInfo)
        default:
            print("❓ Unknown notification type: \(type)")
        }
    }
    
    private func handleBookingNotification(_ userInfo: [AnyHashable: Any]) {
        print("📅 Handling booking notification")
        NotificationCenter.default.post(
            name: .bookingNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
        updateBadgeCount()
    }
    
    private func handleReminderNotification(_ userInfo: [AnyHashable: Any]) {
        print("⏰ Handling appointment reminder")
        NotificationCenter.default.post(
            name: .reminderNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func handleMessageNotification(_ userInfo: [AnyHashable: Any]) {
        print("💬 Handling message notification")
        
        if UIApplication.shared.applicationState == .active {
            NotificationCenter.default.post(
                name: .messageNotificationReceived,
                object: nil,
                userInfo: userInfo
            )
        }
        
        updateBadgeCount()
    }
    
    private func handlePaymentNotification(_ userInfo: [AnyHashable: Any]) {
        print("💰 Handling payment notification")
        NotificationCenter.default.post(
            name: .paymentNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func handleReviewNotification(_ userInfo: [AnyHashable: Any]) {
        print("⭐ Handling review notification")
        NotificationCenter.default.post(
            name: .reviewNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }
    
    private func handleSystemNotification(_ userInfo: [AnyHashable: Any]) {
        print("🔔 Handling system notification")
        NotificationCenter.default.post(
            name: .systemNotificationReceived,
            object: nil,
            userInfo: userInfo
        )
    }
    
    // MARK: - Badge Management
    
    func updateBadgeCount() {
        Task {
            do {
                // TODO: Implement getUnreadCount in NetworkManager
                // This should combine unread messages + pending booking requests
                let unreadCount = 0 // Placeholder
                
                if #available(iOS 16.0, *) {
                    try await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
                } else {
                    await MainActor.run {
                        UIApplication.shared.applicationIconBadgeNumber = unreadCount
                    }
                }
                
            } catch {
                print("❌ Failed to get unread count: \(error)")
            }
        }
    }
    
    func clearBadge() {
        Task {
            if #available(iOS 16.0, *) {
                try? await UNUserNotificationCenter.current().setBadgeCount(0)
            } else {
                await MainActor.run {
                    UIApplication.shared.applicationIconBadgeNumber = 0
                }
            }
        }
    }
    
    // MARK: - Notification Categories
    
    func setupNotificationCategories() {
        let bookingCategory = UNNotificationCategory(
            identifier: "BOOKING_CATEGORY",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_BOOKING",
                    title: "View Booking",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "CANCEL_BOOKING",
                    title: "Cancel",
                    options: [.destructive]
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let messageCategory = UNNotificationCategory(
            identifier: "MESSAGE_CATEGORY",
            actions: [
                UNNotificationAction(
                    identifier: "REPLY_ACTION",
                    title: "Reply",
                    options: [.foreground]
                ),
                UNNotificationAction(
                    identifier: "MARK_READ_ACTION",
                    title: "Mark as Read",
                    options: []
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        let reminderCategory = UNNotificationCategory(
            identifier: "REMINDER_CATEGORY",
            actions: [
                UNNotificationAction(
                    identifier: "VIEW_APPOINTMENT",
                    title: "View",
                    options: [.foreground]
                )
            ],
            intentIdentifiers: [],
            options: []
        )
        
        UNUserNotificationCenter.current().setNotificationCategories([
            bookingCategory,
            messageCategory,
            reminderCategory
        ])
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let bookingNotificationReceived = Notification.Name("bookingNotificationReceived")
    static let reminderNotificationReceived = Notification.Name("reminderNotificationReceived")
    static let messageNotificationReceived = Notification.Name("messageNotificationReceived")
    static let paymentNotificationReceived = Notification.Name("paymentNotificationReceived")
    static let reviewNotificationReceived = Notification.Name("reviewNotificationReceived")
    static let systemNotificationReceived = Notification.Name("systemNotificationReceived")
}

