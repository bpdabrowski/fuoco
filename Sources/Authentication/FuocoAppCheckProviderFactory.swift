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
        let providerFactory = AppCheckDebugProviderFactory()
        #else
        let providerFactory = AppAttestProvider(app: app)
        #endif
        
        return providerFactory
    }
    
//    public init() { }
}
