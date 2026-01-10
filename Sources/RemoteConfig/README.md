# Remote Config Client

A Swift wrapper around Firebase Remote Config with support for the `swift-dependencies` library.

## Features

- ✅ Fetch and activate remote config values
- ✅ Type-safe value retrieval (String, Bool, Number, Data)
- ✅ JSON decoding support for complex configurations
- ✅ Real-time config updates with listener support
- ✅ Default values from plist or dictionary
- ✅ Configurable fetch interval
- ✅ Protocol witness pattern using `swift-dependencies`

## Installation

The RemoteConfig module is already configured in `Package.swift` with dependencies on:
- `FirebaseRemoteConfig` from `firebase-ios-sdk`
- `Dependencies` from `swift-dependencies`

## Basic Setup

### 1. Set Default Values

Set default values that your app will use before fetching from the backend:

```swift
import Dependencies
import RemoteConfig

@Dependency(\.remoteConfig) var remoteConfig

// From dictionary
remoteConfig.setDefaults([
    "welcome_message": "Welcome!" as NSObject,
    "new_feature_flag": false as NSObject,
    "max_items": 10 as NSObject
])

// Or from a plist file
remoteConfig.setDefaultsFromPlist("RemoteConfigDefaults")
```

### 2. Configure Fetch Interval (Optional)

For development, you may want to set a shorter fetch interval:

```swift
// Development: Fetch more frequently (0 = no throttling)
remoteConfig.setMinimumFetchInterval(0)

// Production: Use default 12-hour interval (already set by default)
remoteConfig.setMinimumFetchInterval(43200)
```

### 3. Fetch and Activate Values

```swift
do {
    let changed = try await remoteConfig.fetchAndActivate()
    if changed {
        print("Config was updated from server")
    } else {
        print("Config was already up to date")
    }
} catch {
    print("Error fetching config: \(error)")
}
```

## Getting Values

### Simple Values

```swift
// Get a string value
let welcomeMessage = remoteConfig.getString("welcome_message")

// Get a boolean value
let isFeatureEnabled = remoteConfig.getBool("new_feature_flag")

// Get a number value
let maxItems = remoteConfig.getNumber("max_items").intValue
```

### Complex Values (JSON Decoding)

Define a Codable struct and decode directly from Remote Config:

```swift
struct AppFeatureConfig: Codable {
    let isNewFeatureEnabled: Bool
    let maxUploadSize: Int
    let themeColors: [String: String]
}

do {
    let config = try remoteConfig.getDecoded("app_feature_config", as: AppFeatureConfig.self)
    print("Feature enabled: \(config.isNewFeatureEnabled)")
} catch {
    print("Failed to decode configuration: \(error)")
}
```

## Real-Time Updates

Listen for real-time updates from the Remote Config backend:

```swift
// Start listening for updates
remoteConfig.startListeningForUpdates { updatedKeys in
    print("Config updated! Changed keys: \(updatedKeys)")
    
    // Refresh your UI or app state with the new values
    await MainActor.run {
        // Update UI here
        let newMessage = remoteConfig.getString("welcome_message")
        self.welcomeLabel.text = newMessage
    }
}

// Stop listening when no longer needed
remoteConfig.stopListeningForUpdates()
```

## Complete Example

```swift
import SwiftUI
import Dependencies
import RemoteConfig

struct ContentView: View {
    @Dependency(\.remoteConfig) var remoteConfig
    @State private var welcomeMessage: String = "Loading..."
    @State private var featureEnabled: Bool = false
    @State private var updateTask: Task<Void, Never>?
    
    var body: some View {
        VStack {
            Text(welcomeMessage)
                .padding()
            
            if featureEnabled {
                Text("New Feature is Enabled!")
                    .foregroundColor(.green)
            }
        }
        .task {
            await configureRemoteConfig()
        }
        .onDisappear {
            // Cancel the listening task when view disappears
            updateTask?.cancel()
        }
    }
    
    func configureRemoteConfig() async {
        // Set defaults
        remoteConfig.setDefaults([
            "welcome_message": "Welcome!" as NSObject,
            "new_feature_flag": false as NSObject
        ])
        
        // For development, disable throttling
        #if DEBUG
        remoteConfig.setMinimumFetchInterval(0)
        #endif
        
        // Fetch and activate
        do {
            _ = try await remoteConfig.fetchAndActivate()
            updateUI()
        } catch {
            print("Error fetching config: \(error)")
        }
        
        // Listen for real-time updates using AsyncStream
        updateTask = Task {
            for await updatedKeys in remoteConfig.configUpdates() {
                print("Updated keys: \(updatedKeys)")
                await MainActor.run {
                    updateUI()
                }
            }
        }
    }
    
    func updateUI() {
        welcomeMessage = remoteConfig.getString("welcome_message")
        featureEnabled = remoteConfig.getBool("new_feature_flag")
    }
}
```

## Testing

For testing, you can provide a test implementation using `swift-dependencies`:

```swift
import Dependencies
import XCTest

class MyFeatureTests: XCTestCase {
    func testWithMockConfig() async {
        await withDependencies {
            $0.remoteConfig.getString = { key in
                if key == "welcome_message" {
                    return "Test Welcome"
                }
                return ""
            }
            $0.remoteConfig.getBool = { key in
                if key == "new_feature_flag" {
                    return true
                }
                return false
            }
            $0.remoteConfig.configUpdates = {
                AsyncStream { continuation in
                    // Emit test updates
                    continuation.yield(["welcome_message"])
                    continuation.yield(["new_feature_flag"])
                    continuation.finish()
                }
            }
        } operation: {
            // Test your feature with mock config
            @Dependency(\.remoteConfig) var config
            let message = config.getString("welcome_message")
            XCTAssertEqual(message, "Test Welcome")
            
            // Test listening to updates
            var updates: [[String]] = []
            for await updatedKeys in config.configUpdates() {
                updates.append(updatedKeys)
            }
            XCTAssertEqual(updates.count, 2)
        }
    }
}
```

## Best Practices

1. **Set Defaults First**: Always set default values before fetching to ensure your app works offline
2. **Fetch on App Start**: Fetch and activate during app initialization or startup
3. **Use Real-Time Updates**: Enable real-time listeners with AsyncStream to automatically receive config updates with structured concurrency
4. **Cancel Listeners Properly**: Store the Task and cancel it when no longer needed (e.g., when view disappears)
5. **Production Throttling**: Use the default 12-hour fetch interval in production to avoid throttling
6. **Type Safety**: Use `getDecoded` with Codable structs for complex configurations
7. **Error Handling**: Always handle errors when fetching or decoding values

## Firebase Console Setup

1. Go to the [Firebase Console](https://console.firebase.google.com/)
2. Select your project
3. Navigate to **Remote Config**
4. Add parameters with the same keys you use in your app
5. Set default values and conditional values as needed
6. Publish your changes

## More Information

- [Firebase Remote Config Documentation](https://firebase.google.com/docs/remote-config/ios/get-started)
- [swift-dependencies](https://github.com/pointfreeco/swift-dependencies)
