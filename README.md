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
- **`GoogleService-Info.plist` is committed, deliberately, after locking down Firestore's rules first.** The instinct is to gitignore it, but the plist isn't actually the access boundary — Firestore's REST API doesn't even require it for a request to go through; **Security Rules** are what decide who can read/write what, independent of who holds the config file. Firestore's rules here validate every write's shape (title present and bounded, `status` one of the three real values, no unexpected fields) so a bot scanning public repos for exposed Firebase configs can't inject garbage — verified directly against the live REST API (well-formed write → 200, malformed → 403 in every case tried). There's still no auth, so nothing stops someone from writing many *valid-looking* tasks or clearing the collection; with no real user data involved, that residual risk was an acceptable, deliberate tradeoff for a repo a reviewer needs to run with zero setup. If Firebase weren't configured at all, `UnavailableTaskRemoteStore` would keep the app fully functional offline regardless — that fallback stays in place either way.
- **CloudKit was seriously considered** instead of Firestore — zero third-party dependency, zero secret file to manage, which fits "no undisclosed configuration" better than any Firebase setup could. It was ruled out for two reasons: no paid Apple Developer Program membership was available to reliably provision an iCloud container, and — more fundamentally — CloudKit containers are scoped to the Apple Developer Team that created them, so a reviewer building this on their own machine with their own Apple ID would get an empty container, not the same data, even if the container problem weren't an issue. Firestore's project credentials are shareable across unrelated builds in a way CloudKit's aren't.
- **iOS 26 Liquid Glass styling** throughout (`glassEffect`, the platform's default floating tab/toolbar treatment) since iOS 26 was the only SDK available.
- **A `RootView` gates the board behind a splash screen tied to real startup work**, not a fixed delay — it owns the single `BoardViewModel`, runs the initial `load()` + `syncNow()`, and only then reveals `BoardView`. The splash itself reuses the three status tint colors as a gradient, so the first thing shown already hints at what the app does. Status changes, the sync badge, and row insert/delete are lightly animated for the same reason — not core requirements, but the app builds toward "reorder" and other affordances more convincingly when state changes read as intentional rather than instant.

## Firebase / Firestore setup

`GoogleService-Info.plist` is committed (see the decisions above for why), so **live sync works with zero setup** — clone, open in Xcode, build and run. `FirebaseBootstrap` detects the plist and configures Firebase automatically; `AppDependencies` picks `FirestoreTaskRemoteStore` over the offline fallback at launch.

If you want to point the app at your own Firebase project instead (e.g. to see it running against rules you control):

1. Go to the [Firebase Console](https://console.firebase.google.com), sign in, and create a project.
2. Add an iOS app with bundle ID `com.vaishnav.OfflineTaskBoard`.
3. Download the generated `GoogleService-Info.plist` and replace the one in `OfflineTaskBoard/` (Xcode: drag it in over the existing reference, "Copy items if needed" + the `OfflineTaskBoard` target checked).
4. In the console, go to **Build → Firestore Database → Create database**, and set up rules — the validation rules used here are in the "Known limitations" section below if you want to reuse them.

Deleting the plist entirely also works: the app falls back to `UnavailableTaskRemoteStore` and stays fully usable offline, with sync attempts reporting "not configured" through the same failure path as any other sync failure.

## Run and test

Open `OfflineTaskBoard.xcodeproj` in Xcode, select an iOS 26 simulator, and run. Run the test suite from the Test navigator or `xcodebuild test` — 37 tests across:

- `TaskEditingUseCaseTests` — validation, tombstoning, status changes vs. position, global reorder.
- `TaskSyncUseCaseTests` — upload/pull, per-task failure isolation, tombstone-purge-on-delete, conflict detection and self-resolution.
- `SwiftDataTaskRepositoryTests` — CRUD, ordering, persistence across a fresh repository instance (relaunch equivalent), full round-trip field fidelity.
- `FirestoreTaskRemoteStoreTests` — pure mapping logic (`TaskItem` ⇄ Firestore document fields), no network or emulator involved.
- `UnavailableTaskRemoteStoreTests` — the offline fallback keeps data local and marks it `.failed` rather than losing it.

## Known limitations

- **Firestore's SPM package links into the app target but not the test target.** Firestore's binary dependencies (`abseil`, `leveldb`, `nanopb`, `gRPC-Core`/`gRPC-C++`) fail to link under the test target's separately-built `-enable-testing` variant specifically — a reproducible upstream bug on this Xcode 26 toolchain ([firebase/firebase-ios-sdk#15642](https://github.com/firebase/firebase-ios-sdk/issues/15642), [#14464](https://github.com/firebase/firebase-ios-sdk/issues/14464)), confirmed after exhausting the standard workarounds. Since XCTest unit bundles run in-process inside the host app, `FirestoreTaskRemoteStoreTests` still executes correctly against the app's already-linked symbols — this only affects how the test target itself links, not test coverage.
- **Firestore rules validate shape, not identity.** There's no authentication, so rules can restrict *what* a write looks like but not *who* is writing — someone could still write many valid-looking tasks or clear the collection. Not representative of a real deployment; acceptable for a review window with no real user data. The rules in place:

  ```
  rules_version = '2';
  service cloud.firestore {
    match /databases/{database}/documents {
      match /tasks/{taskId} {
        allow read: if true;
        allow create, update: if request.resource.data.keys().hasOnly(['title','notes','status','sortOrder','createdAt','updatedAt'])
          && request.resource.data.title is string
          && request.resource.data.title.size() > 0 && request.resource.data.title.size() < 300
          && request.resource.data.status in ['todo', 'inProgress', 'done']
          && request.resource.data.sortOrder is number;
        allow delete: if true;
      }
    }
  }
  ```

  Verified directly against the live REST API: well-formed writes return 200; a bad `status` value, an unexpected extra field, and a missing `title` were each independently confirmed to return 403. Unlike Firestore's default test-mode template, these don't have a built-in expiry — they stay in effect until changed.
- **No remote-deletion feed.** If a task were deleted directly in Firestore (bypassing the app), the app has no way to detect that and remove it locally — it would need a dedicated tombstone/deletion feed from the server, which felt like more infrastructure than this exercise needs.
- **No authentication.** All tasks live in one shared `tasks` collection — there's no per-user separation.
- **No background sync.** Sync runs on launch and on manual "Sync" tap only; nothing runs while the app is backgrounded.
- **Reorder is a single global order.** There's no way to independently order tasks within a status the way per-column Kanban ordering would allow — a deliberate tradeoff for the flat-list UI (see decisions above).
- **A pull isn't isolated per document.** `TaskSyncUseCase` pushes each pending task independently (one failure can't block another), but on the pull side `FirestoreTaskRemoteStore.fetchAll()` decodes the whole snapshot in one `map` — one malformed remote document would fail the entire pull for that pass rather than being skipped. Firestore's rules already reject malformed writes from the app itself, so this would only bite from a document edited by hand in the console; still the same class of issue the push-side isolation exists to prevent, just not mirrored on the pull side.

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
- Committing a live Firebase config is acceptable *given* the rules genuinely restrict what can be written (verified above) — the config file itself was never the actual security boundary, so gitignoring it wouldn't have added real protection, only reviewer friction.
- iOS 26 as a minimum deployment target is acceptable, since it's the only SDK available in the build environment.
- "Reorder tasks" (an explicit core requirement) is satisfied by a single global manual ordering rather than per-status ordering, given the flat-list redesign.

## Approximate time spent

Roughly 10–12 hours across architecture and domain design, SwiftData/Firestore integration (including diagnosing the upstream Firestore linker bug above), the test suite, and several rounds of UI iteration based on feedback (Kanban columns → per-status tabs → the current flat list).

## AI tool disclosure

This project was built with Claude Code (Anthropic) as a pairing tool throughout — architecture scaffolding, implementation, debugging (including the Firestore linker investigation), test writing, and iterative UI changes were done in an AI-assisted session. Architectural direction (MVVM + Clean Architecture, SwiftData + Firestore, the flat-list UI redesign, the CloudKit-vs-Firestore call, conflict/reorder semantics) and all product decisions were made by the author through that session, with the expectation of being able to explain and defend every part of it directly.
