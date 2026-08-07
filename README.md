# Offline Task Board

An offline-first iOS task board — built for the Associate Principal iOS Engineer take-home exercise. Every action (create, edit, move, reorder, delete) commits to SwiftData immediately; sync with Firestore happens through an outbox that never blocks the UI and never loses a change, online or off.

## Requirements

- Xcode 26+ (this project was built and tested on Xcode 26.6 / iOS 26.5 SDK — it's the only SDK available in the environment this was built in, so the deployment target is pinned to iOS 26.0)
- An iOS 26 simulator or device

## Architecture

MVVM + Clean Architecture, deliberately **sized to the problem** rather than maximal — a single-entity task board doesn't have enough distinct business logic per CRUD verb to justify one class per action, so the domain layer uses two cohesive use cases instead of eight thin ones.

```
Presentation                Domain                          Data
─────────────                ──────                          ────
BoardView            →      TaskEditingUseCase        →     SwiftDataTaskRepository → SwiftData
BoardViewModel        →     TaskSyncUseCase            →     FirestoreTaskRemoteStore → Firestore
TaskCardView, ...                  ↑                          UnavailableTaskRemoteStore (fallback)
                          TaskRepository /
                          TaskRemoteDataSource (protocols)
```

- **Domain** (`OfflineTaskBoard/Domain`) — `TaskItem`, `TaskStatus`, `SyncStatus` are plain Swift, no SwiftData/Firestore imports. `TaskRepository` and `TaskRemoteDataSource` are the only interfaces anything above Data depends on. `TaskEditingUseCase` covers create/update/delete/restore/move/reorder; `TaskSyncUseCase` owns the outbox, remote pulls, and conflict resolution — both fully unit-testable with in-memory fakes, no framework involved.
- **Data** (`OfflineTaskBoard/Data`) — `SwiftDataTaskRepository` is the only file that knows both `TaskItem` and SwiftData's `TaskModel` exist. `FirestoreTaskRemoteStore` implements the remote protocol against a Firestore `tasks` collection; `UnavailableTaskRemoteStore` is the fallback used whenever Firebase isn't configured, so the app never crashes or blocks on a missing remote.
- **Presentation** (`OfflineTaskBoard/Presentation`) — a single `BoardView` backed by `BoardViewModel` (`@MainActor`, `ObservableObject`). One flat, `sortOrder`-driven list rather than per-status columns — see decisions below.
- **App** (`OfflineTaskBoard/App`) — `AppDependencies` is the composition root; it's the only place a concrete Data-layer type gets wired into a Domain protocol.

## Key technical decisions

- **SwiftData is the local source of truth; Firestore is a pure remote CRUD endpoint.** Firestore has its own built-in offline cache, but using it would silently do the offline-first work this exercise is meant to demonstrate. `TaskSyncUseCase` owns the outbox instead.
- **Outbox via `SyncStatus`** (`synced` / `pendingUpload` / `pendingDelete` / `failed` / `conflicted`) on every task, plus soft-delete tombstones (`isDeleted`) so a delete can be undone before it's confirmed remotely and the remote always finds out about it.
- **Per-task failure isolation.** Each pending task's push happens in its own try/catch inside `TaskSyncUseCase`; one task failing to sync can never block the rest of the outbox.
- **Conflict policy:** each task tracks `lastSyncedUpdatedAt` — the remote timestamp as of the last confirmed sync. If remote and local both changed since that baseline, it's a genuine conflict: local wins immediately (marked `.conflicted` so the UI can say so), and since a `.conflicted` task still counts as "pending," it self-resolves by overwriting the remote on the very next sync pass. If only one side changed, that side's version applies with no conflict.
- **One flat, global list instead of Kanban-style per-status columns.** `sortOrder` is a single ordering across every task regardless of status — changing status is purely a workflow/label change (via a tap-to-cycle status icon on each card, or a "Move to" menu) and never moves a task's position. This came out of iterating on the UI: a per-status column view means a status with many tasks can bury the other columns off-screen; one list keeps everything visible, with the status icon and a small badge as the at-a-glance signal instead of physical grouping.
- **Drag-to-reorder** via SwiftUI List's native `onMove`, gated behind a compact edit-mode toggle in the header (not a full `EditButton()` text label) — swipe-to-delete and the "..." menu handle the rest, so the toggle only appears when you actually want to reorder.
- **No live Firebase credentials are ever committed.** `GoogleService-Info.plist` is gitignored. Without it, `UnavailableTaskRemoteStore` keeps the app fully functional offline, and `TaskSyncUseCase` reports "not configured" through the same failure path as any other sync failure — not a crash, not a special case.
- **CloudKit was seriously considered** instead of Firestore — zero third-party dependency, zero secret file to manage, which fits "no undisclosed configuration" better than any Firebase setup could. It was ruled out for two reasons: no paid Apple Developer Program membership was available to reliably provision an iCloud container, and — more fundamentally — CloudKit containers are scoped to the Apple Developer Team that created them, so a reviewer building this on their own machine with their own Apple ID would get an empty container, not the same data, even if the container problem weren't an issue. Firestore's project credentials are shareable across unrelated builds in a way CloudKit's aren't.
- **iOS 26 Liquid Glass styling** throughout (`glassEffect`, the platform's default floating tab/toolbar treatment) since iOS 26 was the only SDK available.

## Firebase / Firestore setup

The repository intentionally does not include `GoogleService-Info.plist` — Firestore is currently running in open test-mode security rules (see Known limitations), and this file is not a traditional secret but does grant access to that project. To run with live sync:

1. Go to the [Firebase Console](https://console.firebase.google.com), sign in, and create a project.
2. Add an iOS app with bundle ID `com.vaishnav.OfflineTaskBoard`.
3. Download the generated `GoogleService-Info.plist`.
4. Drag it into the `OfflineTaskBoard/` folder in Xcode's project navigator (top-level app folder), with "Copy items if needed" and the `OfflineTaskBoard` target both checked.
5. In the console, go to **Build → Firestore Database → Create database**, start in test mode, pick any region.
6. Build and run — `FirebaseBootstrap` detects the plist and configures Firebase automatically; `AppDependencies` switches from `UnavailableTaskRemoteStore` to `FirestoreTaskRemoteStore` at launch.

Without the plist, the app builds, runs, and is fully usable — sync attempts just report "not configured" instead of connecting.

## Run and test

Open `OfflineTaskBoard.xcodeproj` in Xcode, select an iOS 26 simulator, and run. Run the test suite from the Test navigator or `xcodebuild test` — 37 tests across:

- `TaskEditingUseCaseTests` — validation, tombstoning, status changes vs. position, global reorder.
- `TaskSyncUseCaseTests` — upload/pull, per-task failure isolation, tombstone-purge-on-delete, conflict detection and self-resolution.
- `SwiftDataTaskRepositoryTests` — CRUD, ordering, persistence across a fresh repository instance (relaunch equivalent), full round-trip field fidelity.
- `FirestoreTaskRemoteStoreTests` — pure mapping logic (`TaskItem` ⇄ Firestore document fields), no network or emulator involved.
- `UnavailableTaskRemoteStoreTests` — the offline fallback keeps data local and marks it `.failed` rather than losing it.

## Known limitations

- **Firestore's SPM package links into the app target but not the test target.** Firestore's binary dependencies (`abseil`, `leveldb`, `nanopb`, `gRPC-Core`/`gRPC-C++`) fail to link under the test target's separately-built `-enable-testing` variant specifically — a reproducible upstream bug on this Xcode 26 toolchain ([firebase/firebase-ios-sdk#15642](https://github.com/firebase/firebase-ios-sdk/issues/15642), [#14464](https://github.com/firebase/firebase-ios-sdk/issues/14464)), confirmed after exhausting the standard workarounds. Since XCTest unit bundles run in-process inside the host app, `FirestoreTaskRemoteStoreTests` still executes correctly against the app's already-linked symbols — this only affects how the test target itself links, not test coverage.
- **Firestore security rules are open (test mode)** — no authentication, and the rules auto-expire to deny-all after 30 days. Fine for a review window, not representative of a real deployment.
- **No remote-deletion feed.** If a task were deleted directly in Firestore (bypassing the app), the app has no way to detect that and remove it locally — it would need a dedicated tombstone/deletion feed from the server, which felt like more infrastructure than this exercise needs.
- **No authentication.** All tasks live in one shared `tasks` collection — there's no per-user separation.
- **No background sync.** Sync runs on launch and on manual "Sync" tap only; nothing runs while the app is backgrounded.
- **Reorder is a single global order.** There's no way to independently order tasks within a status the way per-column Kanban ordering would allow — a deliberate tradeoff for the flat-list UI (see decisions above).

## Features deferred (would add with more time)

- Undo for delete (the tombstone pattern already in place makes this cheap to add — it just wasn't reached).
- A lightweight debug/dev mode for simulating offline conditions and sync failures on demand.
- Search/filtering across tasks.
- A more deliberate first-launch/empty-state experience.
- Background sync via `BGTaskScheduler`.
- Retry backoff for repeatedly-failing syncs (currently a failed task just waits for the next manual sync, with no escalating delay).
- Authentication and per-user data.

## Assumptions

- A single shared task list with no authentication is acceptable for this exercise's scope.
- "No undisclosed configuration" is satisfied by documenting the Firebase setup steps above, rather than requiring the repo to build with live sync out of the box — committing real credentials for an openly-writable Firestore project felt like the wrong tradeoff (see Known limitations).
- iOS 26 as a minimum deployment target is acceptable, since it's the only SDK available in the build environment.
- "Reorder tasks" (an explicit core requirement) is satisfied by a single global manual ordering rather than per-status ordering, given the flat-list redesign.

## Approximate time spent

Roughly 10–12 hours across architecture and domain design, SwiftData/Firestore integration (including diagnosing the upstream Firestore linker bug above), the test suite, and several rounds of UI iteration based on feedback (Kanban columns → per-status tabs → the current flat list).

## AI tool disclosure

This project was built with Claude Code (Anthropic) as a pairing tool throughout — architecture scaffolding, implementation, debugging (including the Firestore linker investigation), test writing, and iterative UI changes were done in an AI-assisted session. Architectural direction (MVVM + Clean Architecture, SwiftData + Firestore, the flat-list UI redesign, the CloudKit-vs-Firestore call, conflict/reorder semantics) and all product decisions were made by the author through that session, with the expectation of being able to explain and defend every part of it directly.
