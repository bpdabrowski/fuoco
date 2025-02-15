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
    
    public func response(_ result: Result<ASAuthorization, any Error>, nonce: String?) {
        switch result {
        case .success(let authorization):
            handleSuccessfulLogin(with: authorization, nonce: nonce)
        case .failure(let error):
            handleLoginError(with: error)
        }
    }
    
    private func handleSuccessfulLogin(with authorization: ASAuthorization, nonce: String?) {
        if let appleIDCredential = authorization.credential as? ASAuthorizationAppleIDCredential {

        guard let nonce else {
            fatalError("Invalid state: A login callback was received, but no login request was sent.")
          }
            
          guard let appleIDToken = appleIDCredential.identityToken else {
            print("Unable to fetch identity token")
            return
          }
          guard let idTokenString = String(data: appleIDToken, encoding: .utf8) else {
            print("Unable to serialize token string from data: \(appleIDToken.debugDescription)")
            return
          }
          // Initialize a Firebase credential, including the user's full name.
          let credential = OAuthProvider.appleCredential(withIDToken: idTokenString,
                                                            rawNonce: nonce,
                                                            fullName: appleIDCredential.fullName)
          // Sign in with Firebase.
          Auth.auth().signIn(with: credential) { (authResult, error) in
              print("Hi BD! authResult: \(authResult?.user)")
              print("Hi BD! error: \(error?.localizedDescription)")
    //            if error {
    //              // Error. If error.code == .MissingOrInvalidNonce, make sure
    //              // you're sending the SHA256-hashed nonce as a hex string with
    //              // your request to Apple.
    //              print(error.localizedDescription)
    //              return
    //            }
            // User is signed in to Firebase with Apple.
            // ...
          }
        }
    }

    private func handleLoginError(with error: Error) {
        print("Could not authenticate: \\(error.localizedDescription)")
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
