//
//  UserNotificationClient.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 4/26/25.
//

import Combine
import Dependencies
import FirebaseMessaging
@preconcurrency import UserNotifications

public struct UserNotificationClient {
    public let delegate: @Sendable () -> AsyncStream<DelegateEvent>
    public var requestAuthorization: @Sendable (UNAuthorizationOptions) async throws -> Bool
    public var getNotificationSettings: @Sendable () async -> Notification.Settings = {
      Notification.Settings(authorizationStatus: .notDetermined)
    }
    public var scheduleLocalNotification: @Sendable (UNNotificationRequest) async throws -> Void
    public var unscheduleLocalNotification: @Sendable (String?) -> Void
    public var allScheduledLocalNotifications: @Sendable () async -> [String]
    
    public enum DelegateEvent: Sendable {
        case didReceiveResponse(Notification.Response)
        case openSettingsForNotification(Notification?)
        case willPresentNotification(Notification, @Sendable (UNNotificationPresentationOptions) -> Void)
    }
    
    public struct Notification: Equatable, Sendable {
        public let date: Date
        public let request: UNNotificationRequest
        
        public init(
            date: Date,
            request: UNNotificationRequest
        ) {
            self.date = date
            self.request = request
        }
        
        public struct Response: Equatable, Sendable {
            public let notification: Notification
            
            public init(notification: Notification) {
                self.notification = notification
            }
        }
        
        public struct Settings: Equatable, Sendable {
            public let authorizationStatus: UNAuthorizationStatus
            
            public init(authorizationStatus: UNAuthorizationStatus) {
                self.authorizationStatus = authorizationStatus
            }
        }
    }
}

extension UserNotificationClient: DependencyKey, Sendable {
    public static let liveValue = Self(
        delegate: {
            AsyncStream { continuation in
                let delegate = Delegate(continuation: continuation)
                UNUserNotificationCenter.current().delegate = delegate
                continuation.onTermination = { _ in
                    _ = delegate
                }
            }
        }, requestAuthorization: {
            do {
                return try await UNUserNotificationCenter.current().requestAuthorization(options: $0)
            } catch {
                return false
            }
        }, getNotificationSettings: {
            async let notificationSettings = UNUserNotificationCenter.current().notificationSettings()
            return await Notification.Settings(rawValue: notificationSettings)
        }, scheduleLocalNotification: { request in
            try await UNUserNotificationCenter.current().add(request)
        }, unscheduleLocalNotification: { id in
            guard let id else { return }
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        }, allScheduledLocalNotifications: {
            await UNUserNotificationCenter.current().pendingNotificationRequests().map(\.identifier)
        })
    
    public static let testValue = Self {
        fatalError()
    } requestAuthorization: { _ in
        fatalError()
    } scheduleLocalNotification: { _ in
        fatalError()
    } unscheduleLocalNotification: { _ in
        fatalError()
    } allScheduledLocalNotifications: {
        fatalError()
    }
}

extension DependencyValues {
    public var userNotifications: UserNotificationClient {
        get { self[UserNotificationClient.self] }
        set { self[UserNotificationClient.self] = newValue }
    }
}

extension UserNotificationClient.Notification {
    public init(rawValue: UNNotification) {
        self.date = rawValue.date
        self.request = rawValue.request
    }
}

extension UserNotificationClient.Notification.Response {
    public init(rawValue: UNNotificationResponse) {
        self.notification = .init(rawValue: rawValue.notification)
    }
}

extension UserNotificationClient.Notification.Settings {
    public init(rawValue: UNNotificationSettings) {
        self.authorizationStatus = rawValue.authorizationStatus
    }
}

extension UserNotificationClient {
    @MainActor
    fileprivate final class Delegate: NSObject, @preconcurrency UNUserNotificationCenterDelegate, Sendable {
        private let continuation: AsyncStream<UserNotificationClient.DelegateEvent>.Continuation
        
        nonisolated init(continuation: AsyncStream<UserNotificationClient.DelegateEvent>.Continuation) {
            self.continuation = continuation
        }
        
        func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
            self.continuation.yield(.didReceiveResponse(.init(rawValue: response)))
        }
        
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler: @Sendable @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            self.continuation.yield(.willPresentNotification(.init(rawValue: notification), completionHandler))
        }
        
        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            openSettingsFor notification: UNNotification?
        ) {
            self.continuation.yield(
                .openSettingsForNotification(notification.map(Notification.init(rawValue:)))
            )
        }
    }
}
