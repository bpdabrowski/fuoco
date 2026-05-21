# Fuoco

Fuoco ("fire" in Italian) is a modular Swift package that wraps the Firebase iOS SDK into dependency-injectable clients for use with The Composable Architecture. Built to solve a specific problem: Firebase's SDK exposes global singletons that are difficult to mock, making TCA reducers that touch Firebase nearly impossible to unit test. Fuoco wraps each service behind a `DependencyKey`-conforming client so reducers stay testable and Firebase stays swappable.

Used in production by [Foam](https://github.com/bdabrowski/foam).

> Swift 6.0+ &nbsp;|&nbsp; iOS 17+ &nbsp;|&nbsp; Firebase iOS SDK 11.6+

---

## Modules

| Module | What it wraps |
|---|---|
| **Networking** | Firestore CRUD + real-time `AsyncThrowingStream` listeners |
| **Authentication** | Sign in with Apple, token management, App Check |
| **CloudFunctions** | Callable Firebase Functions |
| **Storage** | Image upload with JPEG compression |
| **RemoteNotifications** | Push notifications, local scheduling, badge management |
| **Analytics** | User ID and property tracking |

---

## Engineering notes

**`FirestoreParser`** — Firebase's `GeoPoint` and `Timestamp` types crash standard `JSONEncoder`. `FirestoreParser` handles the conversion before decoding, and automatically injects the Firestore document ID into the `id` field when the document data doesn't already contain one.

**Real-time listeners** — Firestore snapshot listeners are vended as `AsyncThrowingStream`, tying listener lifecycle to Swift structured concurrency. Listeners start when the stream is iterated and are cleaned up automatically on cancellation.

**Swift 6 concurrency** — All clients conform to `Sendable`. Firebase SDK types that predate strict concurrency are bridged with `@preconcurrency` imports rather than suppressed warnings.

**Write debounce** — `setData` has a 750ms debounce via `Task.sleep` to reduce unnecessary Firestore writes during rapid state updates.

**App Check** — Uses `AppAttestProvider` on device and `AppCheckDebugProvider` on simulator, gated with `#if !targetEnvironment(simulator)`.
