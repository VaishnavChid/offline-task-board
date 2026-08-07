//
//  SwiftDataTaskRepositoryTests.swift
//  OfflineTaskBoardTests
//
//  Created by Vaishnav on 07/08/26.
//

import XCTest
import SwiftData
@testable import OfflineTaskBoard

@MainActor
final class SwiftDataTaskRepositoryTests: XCTestCase {
    private var container: ModelContainer!
    private var repository: SwiftDataTaskRepository!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: TaskModel.self, configurations: configuration)
        repository = SwiftDataTaskRepository(context: container.mainContext)
    }

    func testUpsertInsertsNewTask() throws {
        let task = TaskItem(title: "Persisted", status: .todo, sortOrder: 0)
        try repository.upsert(task)

        let stored = try repository.allTasks()
        XCTAssertEqual(stored.map(\.id), [task.id])
        XCTAssertEqual(stored.first?.title, "Persisted")
    }

    func testUpsertUpdatesExistingTaskInPlaceRatherThanDuplicating() throws {
        let task = TaskItem(title: "Draft", status: .todo, sortOrder: 0)
        try repository.upsert(task)

        var edited = task
        edited.title = "Final"
        try repository.upsert(edited)

        let stored = try repository.allTasks()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.title, "Final")
    }

    func testAllTasksAreSortedBySortOrder() throws {
        try repository.upsert(TaskItem(title: "Second", status: .todo, sortOrder: 1))
        try repository.upsert(TaskItem(title: "First", status: .todo, sortOrder: 0))

        XCTAssertEqual(try repository.allTasks().map(\.title), ["First", "Second"])
    }

    func testPendingTasksExcludesSyncedTasks() throws {
        var synced = TaskItem(title: "Synced", status: .todo, sortOrder: 0)
        synced.syncStatus = .synced
        let pending = TaskItem(title: "Pending", status: .todo, sortOrder: 1)
        try repository.upsert(synced)
        try repository.upsert(pending)

        XCTAssertEqual(try repository.pendingTasks().map(\.title), ["Pending"])
    }

    func testHardDeleteRemovesTask() throws {
        let task = TaskItem(title: "Temp", status: .todo, sortOrder: 0)
        try repository.upsert(task)
        try repository.hardDelete(id: task.id)

        XCTAssertEqual(try repository.allTasks().count, 0)
    }

    func testHardDeleteOnMissingIDIsANoOp() throws {
        XCTAssertNoThrow(try repository.hardDelete(id: UUID()))
    }

    /// Stands in for "survives an app relaunch": a second repository over the same underlying
    /// store sees exactly what the first one wrote.
    func testTasksAreVisibleToAnotherRepositoryInstanceOverTheSameStore() throws {
        let task = TaskItem(title: "Survives relaunch", status: .inProgress, sortOrder: 0)
        try repository.upsert(task)

        let anotherRepository = SwiftDataTaskRepository(context: container.mainContext)
        XCTAssertEqual(try anotherRepository.allTasks().map(\.title), ["Survives relaunch"])
    }

    /// Regression test for a real bug: `TaskModel` used to name its soft-delete flag `isDeleted`,
    /// which collides with the read-only `isDeleted` Core Data already defines on every managed
    /// object (SwiftData is Core Data-backed) to mean "removed from its context" — a different
    /// thing entirely from our own tombstone flag. Writing `true` to that property succeeded in
    /// memory, but a *fresh* fetch — exactly what `deleteTask` → `loadBoard` do back-to-back —
    /// read the same row back with the flag reset to `false`. Found live: deleting a task made it
    /// slide off screen, then reappear moments later — the sync engine saw `isDeleted == false`
    /// and re-uploaded it as a normal edit instead of deleting it. This test upserts a task, then
    /// upserts it again with `isDeleted = true` (the exact update-in-place path `deleteTask` uses,
    /// not a fresh insert), and re-fetches through a brand-new repository instance over the same
    /// store to rule out any in-memory object identity masking the bug.
    func testSoftDeleteFlagSurvivesAFreshFetch() throws {
        let task = TaskItem(title: "Soft delete me", status: .todo, sortOrder: 0)
        try repository.upsert(task)

        var tombstoned = task
        tombstoned.isDeleted = true
        tombstoned.syncStatus = .pendingDelete
        try repository.upsert(tombstoned)

        let anotherRepository = SwiftDataTaskRepository(context: container.mainContext)
        let refetched = try anotherRepository.allTasks().first
        XCTAssertEqual(refetched?.isDeleted, true)
        XCTAssertEqual(refetched?.syncStatus, .pendingDelete)
    }

    func testRoundTripPreservesAllFields() throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let task = TaskItem(
            title: "Full fidelity", notes: "with notes", status: .done, sortOrder: 3,
            createdAt: now, updatedAt: now.addingTimeInterval(60), syncStatus: .conflicted,
            isDeleted: false, lastSyncedUpdatedAt: now.addingTimeInterval(30)
        )
        try repository.upsert(task)

        XCTAssertEqual(try repository.allTasks().first, task)
    }
}
