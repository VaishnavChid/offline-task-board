//
//  TaskSyncUseCaseTests.swift
//  OfflineTaskBoardTests
//
//  Created by Vaishnav on 07/08/26.
//

import XCTest
@testable import OfflineTaskBoard

@MainActor
final class TaskSyncUseCaseTests: XCTestCase {
    private var repository: InMemoryTaskRepository!
    private var remote: RecordingRemoteDataSource!
    private var useCase: TaskSyncUseCase!

    override func setUp() {
        super.setUp()
        repository = InMemoryTaskRepository()
        remote = RecordingRemoteDataSource()
        useCase = TaskSyncUseCase(repository: repository, remote: remote)
    }

    func testSyncUploadsPendingTaskAndMarksSynced() async throws {
        let task = TaskItem(title: "Ship it", status: .todo, sortOrder: 0)
        try repository.upsert(task)

        let summary = await useCase.sync()

        XCTAssertEqual(summary.uploaded, 1)
        let stored = try repository.allTasks().first
        XCTAssertEqual(stored?.syncStatus, .synced)
        XCTAssertEqual(stored?.lastSyncedUpdatedAt, task.updatedAt)
        let saved = await remote.savedTasks
        XCTAssertEqual(saved.map(\.id), [task.id])
    }

    /// Regression test: the previous sync coordinator threw on the first failed task and aborted
    /// the entire batch, leaving every other pending task stuck. Each task must be isolated.
    func testSyncIsolatesFailureSoOtherPendingTasksStillSync() async throws {
        let willFail = TaskItem(title: "Flaky", status: .todo, sortOrder: 0)
        let willSucceed = TaskItem(title: "Fine", status: .todo, sortOrder: 1)
        try repository.upsert(willFail)
        try repository.upsert(willSucceed)
        await remote.failSaving(id: willFail.id)

        let summary = await useCase.sync()

        XCTAssertEqual(summary.uploaded, 1)
        XCTAssertEqual(summary.failed, 1)
        let stored = Dictionary(uniqueKeysWithValues: try repository.allTasks().map { ($0.id, $0) })
        XCTAssertEqual(stored[willFail.id]?.syncStatus, .failed)
        XCTAssertEqual(stored[willSucceed.id]?.syncStatus, .synced)
    }

    func testSyncDeletesTombstoneRemotelyThenPurgesLocally() async throws {
        var tombstoned = TaskItem(title: "Gone", status: .todo, sortOrder: 0)
        tombstoned.isDeleted = true
        tombstoned.syncStatus = .pendingDelete
        try repository.upsert(tombstoned)

        let summary = await useCase.sync()

        XCTAssertEqual(summary.uploaded, 1)
        XCTAssertEqual(try repository.allTasks().count, 0)
        let deleted = await remote.deletedIDs
        XCTAssertEqual(deleted, [tombstoned.id])
    }

    func testSyncPullsNewRemoteTaskNotPresentLocally() async throws {
        let fromServer = TaskItem(title: "From another device", status: .done, sortOrder: 0, syncStatus: .synced)
        await remote.stubFetch([fromServer])

        let summary = await useCase.sync()

        XCTAssertEqual(summary.pulled, 1)
        XCTAssertEqual(try repository.allTasks().map(\.id), [fromServer.id])
    }

    func testSyncNeverOverwritesATaskThatFailedToUpload() async throws {
        let id = UUID()
        var local = TaskItem(id: id, title: "My unsynced edit", status: .todo, sortOrder: 0)
        try repository.upsert(local)
        await remote.failSaving(id: id)

        var staleRemote = local
        staleRemote.title = "Someone else's edit"
        staleRemote.updatedAt = local.updatedAt.addingTimeInterval(120)
        await remote.stubFetch([staleRemote])

        let summary = await useCase.sync()

        XCTAssertEqual(summary.failed, 1)
        XCTAssertEqual(summary.pulled, 0)
        XCTAssertEqual(try repository.allTasks().first?.title, "My unsynced edit")
    }

    func testSyncDetectsConflictWhenBothSidesChangedSinceBaseline() async throws {
        let id = UUID()
        let baseline = Date(timeIntervalSince1970: 1_000)
        let local = TaskItem(
            id: id, title: "Local edit", status: .todo, sortOrder: 0,
            updatedAt: baseline.addingTimeInterval(60), syncStatus: .synced, lastSyncedUpdatedAt: baseline
        )
        try repository.upsert(local)

        var remoteVersion = local
        remoteVersion.title = "Remote edit"
        remoteVersion.updatedAt = baseline.addingTimeInterval(90)
        await remote.stubFetch([remoteVersion])

        let summary = await useCase.sync()

        XCTAssertEqual(summary.conflicted, 1)
        // The outbox drain runs right after conflict detection in the same sync() call, so a
        // genuine conflict resolves within this pass rather than waiting for a future one.
        XCTAssertEqual(summary.uploaded, 1)
        let stored = try repository.allTasks().first
        XCTAssertEqual(stored?.title, "Local edit", "local must win a genuine conflict")
        XCTAssertEqual(stored?.syncStatus, .synced)
        let saved = await remote.savedTasks
        XCTAssertEqual(saved.map(\.title), ["Local edit"])
    }

    /// Regression test for a real bug: `sync()` used to push the outbox *before* pulling, so a
    /// pending local edit was written to the server with an unconditional `setData` — no
    /// read-before-write — before anything ever compared it against a concurrent remote change.
    /// A genuine conflict (both sides changed since the last confirmed sync) was silently
    /// clobbered rather than detected: this exact scenario, reproduced live against a real
    /// Firestore project, showed "All changes synced" with no conflict indication at all, and the
    /// concurrent remote edit vanished without a trace. This test builds local state the way the
    /// app actually produces it — via a real pending edit, not an artificially-constructed
    /// `.synced`-with-a-future-timestamp task — so it fails against the old push-first ordering
    /// and passes now that `sync()` pulls first.
    func testSyncDetectsConflictWhenLocalHasARealUnsyncedEditAndRemoteAlsoChanged() async throws {
        let id = UUID()
        let baseline = Date(timeIntervalSince1970: 5_000)
        var local = TaskItem(
            id: id, title: "Original", status: .todo, sortOrder: 0,
            updatedAt: baseline, syncStatus: .synced, lastSyncedUpdatedAt: baseline
        )
        try repository.upsert(local)

        // A real, unsynced local edit — exactly what TaskEditingUseCase produces, not a
        // hand-constructed conflicted state.
        local.title = "My local edit"
        local.updatedAt = baseline.addingTimeInterval(30)
        local.syncStatus = .pendingUpload
        try repository.upsert(local)

        // Someone else changed it remotely in the meantime.
        var remoteVersion = local
        remoteVersion.title = "Someone else's edit"
        remoteVersion.updatedAt = baseline.addingTimeInterval(60)
        remoteVersion.syncStatus = .synced
        await remote.stubFetch([remoteVersion])

        let summary = await useCase.sync()

        XCTAssertEqual(summary.conflicted, 1)
        XCTAssertEqual(summary.uploaded, 1)
        let stored = try repository.allTasks().first
        XCTAssertEqual(stored?.title, "My local edit", "local must win a genuine conflict")
        XCTAssertEqual(stored?.syncStatus, .synced)
        let saved = await remote.savedTasks
        XCTAssertEqual(saved.map(\.title), ["My local edit"])
    }

    func testSyncResolvesConflictOnNextPassByPushingLocal() async throws {
        let id = UUID()
        let conflicted = TaskItem(id: id, title: "Local should win", status: .todo, sortOrder: 0, syncStatus: .conflicted)
        try repository.upsert(conflicted)

        let summary = await useCase.sync()

        XCTAssertEqual(summary.uploaded, 1)
        XCTAssertEqual(try repository.allTasks().first?.syncStatus, .synced)
        let saved = await remote.savedTasks
        XCTAssertEqual(saved.map(\.id), [id])
    }

    func testSyncPullsRemoteUpdateWhenOnlyRemoteChanged() async throws {
        let id = UUID()
        let baseline = Date(timeIntervalSince1970: 2_000)
        let local = TaskItem(
            id: id, title: "Old title", status: .todo, sortOrder: 0,
            updatedAt: baseline, syncStatus: .synced, lastSyncedUpdatedAt: baseline
        )
        try repository.upsert(local)

        var remoteVersion = local
        remoteVersion.title = "New title from server"
        remoteVersion.updatedAt = baseline.addingTimeInterval(30)
        await remote.stubFetch([remoteVersion])

        let summary = await useCase.sync()

        XCTAssertEqual(summary.pulled, 1)
        XCTAssertEqual(try repository.allTasks().first?.title, "New title from server")
    }

    func testSyncSurvivesRemoteFetchFailureWithoutLosingLocalState() async throws {
        let task = TaskItem(title: "Stays local", status: .todo, sortOrder: 0, syncStatus: .synced)
        try repository.upsert(task)
        let unreachable = TaskSyncUseCase(repository: repository, remote: ThrowingRemoteDataSource())

        let summary = await unreachable.sync()

        XCTAssertEqual(summary.pulled, 0)
        XCTAssertEqual(try repository.allTasks().count, 1)
    }
}
