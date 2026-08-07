# Offline Task Board

An iOS 17+ SwiftUI task board submitted for the Associate Principal Engineer exercise. It is offline-first: every user action commits to SwiftData before any network work starts. Sync uses an outbox encoded by `syncState` and deletion tombstones, so failed or offline operations remain safe to retry.

## Architecture

`BoardView -> BoardViewModel -> TaskRepository / SyncCoordinator -> SwiftData + TaskRemoteStore`.

- `TaskRecord` is a framework-independent value type; business behavior is testable with an in-memory repository and remote fake.
- SwiftData is the source of truth for the UI. `TaskEntity` persists status, ordering, timestamps, sync state, and tombstones.
- `SyncCoordinator` writes queued changes first, then merges newer remote records. A pending local change is never overwritten by a fetch.
- Firebase is hidden behind `TaskRemoteStore`; users can continue working if cloud setup or connectivity is unavailable.

## Firebase setup

1. In Xcode, add Firebase iOS SDK package: `https://github.com/firebase/firebase-ios-sdk`, products `FirebaseCore` and `FirebaseFirestore`.
2. Add `GoogleService-Info.plist` from your Firebase project (do not commit it).
3. Build and run. `FirebaseBootstrap` configures Firebase exactly once; the `FirebaseTaskRemoteStore` is already a Firestore adapter using the `tasks` collection.

The repository intentionally compiles a safe offline adapter when Firebase packages/configuration are absent rather than relying on hidden credentials. Local mutations remain visibly queued.

## Run and test

Open the project in Xcode, select an iOS 17+ simulator, and run. Run `OfflineTaskBoardTests` from the Test navigator. Tests cover local writes and failure retention; add a fake successful remote to cover acknowledgement and merge policy.

## Decisions and limits

- Conflict policy: local unsynced work wins; otherwise newest `updatedAt` wins. Server timestamps/version vectors are the recommended next step for multi-device editing.
- Reordering is represented by `sortOrder`; drag-reordering can be added by assigning sequential values in one transaction.
- The UI exposes create, edit, delete, move, per-task sync status, and manual/launch sync. Given the 8-10 hour scope, production auth, background refresh, and a full Firestore adapter are documented next steps instead of being stubbed with fake credentials.
- Approximate implementation time: 8-10 hours. AI assistance: used to accelerate scaffolding and documentation; architecture and trade-offs should be reviewed by the author before submission.
