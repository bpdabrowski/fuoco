//
//  RemoteConfigClient.swift
//  fuoco
//
//  Created by Brendyn Dabrowski on 1/4/26.
//

import Dependencies
import FirebaseRemoteConfig
import Foundation

/// A client for interacting with Firebase Remote Config
public struct RemoteConfigClient: Sendable {
    /// Fetch and activate remote config values
    public var fetchAndActivate: @Sendable () async throws -> Bool
    
    /// Get a string value for a given key
    public var getString: @Sendable (String) -> String
    
    /// Get a boolean value for a given key
    public var getBool: @Sendable (String) -> Bool
    
    /// Get a number value for a given key
    public var getNumber: @Sendable (String) -> NSNumber
    
    /// Get a data value for a given key
    public var getData: @Sendable (String) -> Data
    
    /// Get a decoded value for a given key
    public var getDecoded: @Sendable <T: Decodable>(String, T.Type) throws -> T
    
    /// Start listening for real-time config updates
    public var startListeningForUpdates: @Sendable (@Sendable ([String]) async -> Void) -> Void
    
    /// Stop listening for real-time config updates
    public var stopListeningForUpdates: @Sendable () -> Void
    
    /// Set default values from a plist file
    public var setDefaultsFromPlist: @Sendable (String) -> Void
    
    /// Set default values from a dictionary
    public var setDefaults: @Sendable ([String: NSObject]) -> Void
    
    /// Set minimum fetch interval (for development/testing)
    public var setMinimumFetchInterval: @Sendable (TimeInterval) -> Void
}

extension RemoteConfigClient: DependencyKey {
    public static var liveValue: RemoteConfigClient {
        let remoteConfig = RemoteConfig.remoteConfig()
        
        // Configure settings with default 12-hour interval (production)
        let settings = RemoteConfigSettings()
        settings.minimumFetchInterval = 43200 // 12 hours in seconds
        remoteConfig.configSettings = settings
        
        // Actor to manage the listener lifecycle
        actor ListenerManager {
            private var listener: ConfigUpdateListenerRegistration?
            
            func setListener(_ listener: ConfigUpdateListenerRegistration) {
                self.listener?.remove()
                self.listener = listener
            }
            
            func removeListener() {
                listener?.remove()
                listener = nil
            }
        }
        
        let listenerManager = ListenerManager()
        
        return RemoteConfigClient(
            fetchAndActivate: {
                try await withCheckedThrowingContinuation { continuation in
                    remoteConfig.fetchAndActivate { status, error in
                        if let error = error {
                            continuation.resume(throwing: error)
                        } else {
                            let changed = status == .successFetchedFromRemote
                            continuation.resume(returning: changed)
                        }
                    }
                }
            },
            getString: { key in
                remoteConfig[key].stringValue ?? ""
            },
            getBool: { key in
                remoteConfig[key].boolValue
            },
            getNumber: { key in
                remoteConfig[key].numberValue
            },
            getData: { key in
                remoteConfig[key].dataValue
            },
            getDecoded: { key, type in
                let value = remoteConfig[key]
                let data = value.dataValue
                let decoder = JSONDecoder()
                return try decoder.decode(type, from: data)
            },
            startListeningForUpdates: { onUpdate in
                let listener = remoteConfig.addOnConfigUpdateListener { configUpdate, error in
                    guard let configUpdate = configUpdate, error == nil else {
                        print("Error listening for config updates: \(String(describing: error))")
                        return
                    }
                    
                    print("Remote Config updated keys: \(configUpdate.updatedKeys)")
                    
                    // Activate the new config
                    remoteConfig.activate { _, error in
                        if let error = error {
                            print("Error activating config: \(error.localizedDescription)")
                            return
                        }
                        
                        // Call the update handler with the updated keys
                        Task {
                            await onUpdate(Array(configUpdate.updatedKeys))
                        }
                    }
                }
                
                Task {
                    await listenerManager.setListener(listener)
                }
            },
            stopListeningForUpdates: {
                Task {
                    await listenerManager.removeListener()
                }
            },
            setDefaultsFromPlist: { fileName in
                remoteConfig.setDefaults(fromPlist: fileName)
            },
            setDefaults: { defaults in
                remoteConfig.setDefaults(defaults)
            },
            setMinimumFetchInterval: { interval in
                let settings = RemoteConfigSettings()
                settings.minimumFetchInterval = interval
                remoteConfig.configSettings = settings
            }
        )
    }
}

extension DependencyValues {
    public var remoteConfig: RemoteConfigClient {
        get { self[RemoteConfigClient.self] }
        set { self[RemoteConfigClient.self] = newValue }
    }
}
