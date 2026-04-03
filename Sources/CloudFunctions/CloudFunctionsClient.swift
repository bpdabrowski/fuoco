//
//  CloudFunctionsClient.swift
//  fuoco
//

import Dependencies
import FirebaseFunctions

public struct CloudFunctionsClient: Sendable {
    public var call: @Sendable (String, [String: Any]) async throws -> [String: Any]

    public init(call: @escaping @Sendable (String, [String: Any]) async throws -> [String: Any]) {
        self.call = call
    }
}

extension CloudFunctionsClient: DependencyKey {
    public static let liveValue = CloudFunctionsClient { name, params in
        let functions = Functions.functions(region: "us-west1")
        let result = try await functions.httpsCallable(name).call(params)
        return result.data as? [String: Any] ?? [:]
    }

    public static let testValue = CloudFunctionsClient { _, _ in [:] }
}

extension DependencyValues {
    public var cloudFunctions: CloudFunctionsClient {
        get { self[CloudFunctionsClient.self] }
        set { self[CloudFunctionsClient.self] = newValue }
    }
}
