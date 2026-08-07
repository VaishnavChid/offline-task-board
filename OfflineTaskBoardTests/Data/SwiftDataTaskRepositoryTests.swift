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
