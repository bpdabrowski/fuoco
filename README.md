# Fuoco

*"Fire" in Italian* — a modular Firebase abstraction layer for the [Foam](https://github.com/foaminc) iOS app.

Fuoco wraps Firebase services into dependency-injectable Swift clients using [swift-dependencies](https://github.com/pointfreeco/swift-dependencies), making them testable and composable with [The Composable Architecture (TCA)](https://github.com/pointfreeco/swift-composable-architecture).

## Requirements

- iOS 17.0+
- Swift 6.0+
- Firebase iOS SDK 11.6.0+

## Modules

| Module | What it does | Key types |
|---|---|---|
| **Networking** | Firestore CRUD, real-time listeners, type-safe queries | `FirestoreService`, `FirestoreEndpoint`, `FirestoreParser` |
| **Authentication** | Sign in with Apple, token management, App Check | `AuthenticationClient`, `SignInWithApple`, `FuocoAppCheckProviderFactory` |
| **CloudFunctions** | Callable Firebase Functions (us-west1) | `CloudFunctionsClient` |
| **Storage** | Image upload with compression | `StorageClient` |
| **RemoteNotifications** | Push notifications, local scheduling, badge management | `UserNotificationClient` |
| **Analytics** | User ID and property tracking | `AnalyticsClient` |

## Usage

Add fuoco as a local package dependency in your Xcode project, then import the modules you need:

```swift
import Networking
import Authentication
import CloudFunctions
```

All clients are available via `@Dependency`:

```swift
@Dependency(\.firestoreService) var firestoreService
@Dependency(\.auth) var auth
@Dependency(\.cloudFunctions) var cloudFunctions
```

### Firestore queries

Define endpoints using `FirestoreEndpoint`:

```swift
enum BubbleRequest: FirestoreEndpoint {
    case bubbleDetails(String)

    var reference: FirestoreReference {
        switch self {
        case .bubbleDetails(let id):
            return .document("bubbleDetails/\(id)")
        }
    }
}
```

Then use `FirestoreService` to fetch:

```swift
let bubble: BubbleDetails = try await firestoreService.request(
    BubbleRequest.bubbleDetails(id)
)
```

### Real-time listeners

```swift
let stream: AsyncThrowingStream<[SurfReport], Error> =
    firestoreService.listener(BubbleRequest.getSurfConditions(bubbleId))

for try await reports in stream {
    // Handle updates
}
```

### Authentication

```swift
// Sign in with Apple
let result = try await auth.siwa().signIn()

// Check credential state
let isSignedIn = await auth.siwa().isSignedIn()
```

### Cloud Functions

```swift
let result = try await cloudFunctions.call("createGroup", [
    "name": "Surf Crew",
    "memberIds": ["uid1", "uid2"]
])
```

## Architecture

- **DependencyKey pattern** — every client conforms to `DependencyKey` with `liveValue` and `testValue`, enabling dependency injection via TCA
- **Sendable** — all clients are `Sendable` for safe async/await usage
- **FirestoreIdentifiable** — protocol requiring `var id: String` for Firestore model decoding. If the document data already contains an `id` field, it is preserved; otherwise the Firestore document ID is injected
- **FirestoreParser** — handles Firebase-specific types (GeoPoint, Timestamp) that don't serialize cleanly with standard `JSONEncoder`

## Gotchas

- **GeoPoint crashes with Swift JSONEncoder** — always use `FirestoreParser` for documents containing GeoPoint fields, never raw `JSONEncoder`
- **Document ID injection** — `FirestoreService` only injects the Firestore document ID when the data doesn't already have an `id` field. Some models (e.g. `Bubble`) store a cross-collection reference in `id` that must not be overwritten
- **App Check on simulator** — App Check is skipped on simulator (`#if !targetEnvironment(simulator)`). On device, `AppAttestProvider` is used
- **Firestore write debounce** — `setData` has a 750ms debounce to reduce unnecessary writes
