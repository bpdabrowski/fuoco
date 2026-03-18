//
//  FuocoAppCheckProviderFactory.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 7/19/25.
//

import FirebaseAppCheck
import Foundation
import FirebaseCore

public class FuocoAppCheckProviderFactory: NSObject, AppCheckProviderFactory {
    public func createProvider(with app: FirebaseApp) -> AppCheckProvider? {
        #if targetEnvironment(simulator)
        return AppCheckDebugProvider(app: app)
        #else
        return AppAttestProvider(app: app)
        #endif
    }
}
