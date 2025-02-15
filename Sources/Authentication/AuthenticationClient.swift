//
//  AuthenticationClient.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 2/6/25.
//

import Dependencies
import Foundation
import FirebaseAuth
import CryptoKit

public struct AuthenticationClient {
    public var siwa: @Sendable () -> SignInWithApple
    public var currentUser: @Sendable () -> FirebaseAuth.User?
    public var signOut: @Sendable () -> Void
}

extension AuthenticationClient: DependencyKey, Sendable {
    public static var liveValue: AuthenticationClient {
        AuthenticationClient(
            siwa: {
                @Dependency(\.signInWithApple) var siwa
                return siwa
            },
            currentUser: {
                Auth.auth().currentUser
            },
            signOut: {
                try? Auth.auth().signOut()
            }
        )
    }
}

extension DependencyValues: Sendable {
    public var auth: AuthenticationClient {
        get { self[AuthenticationClient.self] }
        set { self[AuthenticationClient.self] = newValue }
    }
}
