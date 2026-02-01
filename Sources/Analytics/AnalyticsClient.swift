//
//  AnalyticsClient.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 1/1/26.
//

import Dependencies
import FirebaseAnalytics

public struct AnalyticsClient {
    public var setUserId: @Sendable (String?) -> Void
    public var setUserProperty: @Sendable (String, String) -> Void
}

extension AnalyticsClient: DependencyKey, Sendable {
    public static var liveValue: AnalyticsClient {
        AnalyticsClient(
            setUserId: { userId in
                Analytics.setUserID(userId)
            },
            setUserProperty: { name, value in
                Analytics.setUserProperty(value, forName: name)
            }
        )
    }
}

extension DependencyValues {
    public var analytics: AnalyticsClient {
        get { self[AnalyticsClient.self] }
        set { self[AnalyticsClient.self] = newValue }
    }
}
