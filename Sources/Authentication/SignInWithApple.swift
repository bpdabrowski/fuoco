//
//  SignInWithApple.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 2/14/25.
//

import AuthenticationServices
import Dependencies
import FirebaseAuth

public struct SignInWithApple: AuthProvider, Sendable {
    public func signIn(with data: ASAuthorizationAppleIDRequest) -> String? {
        let nonce = randomNonceString()
        data.requestedScopes = [.fullName, .email]
        data.nonce = sha256(nonce)
        return data.nonce
    }
    
    public func response(_ result: ASAuthorization, nonce: String?) async throws(AuthError) -> AuthDataResult {
        do {
            return try await handleSuccessfulLogin(with: result, nonce: nonce)
        } catch {
            throw .unableToSignIn
        }
    }
    
    private func handleSuccessfulLogin(
        with authorization: ASAuthorization,
        nonce: String?
    ) async throws(AuthError) -> AuthDataResult {
        guard let nonce else {
            fatalError("Invalid state: A login callback was received, but no login request was sent.")
        }
        
        guard let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
            let appleIDToken = appleIDCredential.identityToken,
            let idTokenString = String(data: appleIDToken, encoding: .utf8)
        else {
            throw .unableToBuildCredential
        }
        
        let credential = OAuthProvider.appleCredential(
            withIDToken: idTokenString,
            rawNonce: nonce,
            fullName: appleIDCredential.fullName
        )
         
        do {
            // The onCreate function doesn't work in firebase functions so it looks like we have to manually add the
            // users name to the database.
            return try await Auth.auth().signIn(with: credential)
        } catch {
            throw .unableToSignIn
        }
    }
    
    public func isSignedIn() async -> Bool {
        return await credentials() == .authorized
    }
    
    public func credentials() async -> ASAuthorizationAppleIDProvider.CredentialState {
        let appleIDProvider = ASAuthorizationAppleIDProvider()
        let providerData = Auth.auth().currentUser?.providerData
        
        guard let appleProviderData = providerData?.first(where: { $0.providerID == "apple.com" }) else {
            return .notFound
        }
        
        do {
            return try await appleIDProvider.credentialState(forUserID: appleProviderData.uid)
        } catch {
            return .notFound
        }
    }
    
    public func verifySignInWithAppleID() async {
        switch await credentials() {
        case .authorized:
            break
        case .revoked, .notFound:
            try? await Auth.auth().signOut()
            // TODO: Token revocation https://firebase.google.com/docs/auth/ios/apple#token_revocation
        default:
            break
        }
    }
}

extension SignInWithApple: DependencyKey {
    public nonisolated static var liveValue: Self {
        return Self()
    }
    
    public nonisolated static var testValue: Self {
        return Self()
    }
}

extension DependencyValues: Sendable {
    var signInWithApple: SignInWithApple {
        get { self[SignInWithApple.self] }
        set { self[SignInWithApple.self] = newValue }
    }
}
