//
//  TaskEditingUseCaseTests.swift
//  OfflineTaskBoardTests
//
//  Created by Vaishnav on 07/08/26.
//

import XCTest
@testable import OfflineTaskBoard

@MainActor
final class TaskEditingUseCaseTests: XCTestCase {
    private var repository: InMemoryTaskRepository!
    private var useCase: TaskEditingUseCase!

    override func setUp() {
        super.setUp()
        repository = InMemoryTaskRepository()
        useCase = TaskEditingUseCase(repository: repository)
    }

    func testCreateTaskTrimsTitleAndMarksPendingUpload() throws {
        let task = try useCase.createTask(title: "  Ship it  ", notes: " release notes ")
        XCTAssertEqual(task.title, "Ship it")
        XCTAssertEqual(task.notes, "release notes")
        XCTAssertEqual(task.syncStatus, .pendingUpload)
        XCTAssertEqual(try repository.allTasks().count, 1)
    }

    func testCreateTaskWithBlankTitleThrowsAndDoesNotPersist() {
        XCTAssertThrowsError(try useCase.createTask(title: "   ", notes: "")) { error in
            XCTAssertTrue(error is TaskValidationError)
        }
        XCTAssertEqual(try? repository.allTasks().count, 0)
    }

    func testCreateTaskAssignsIncrementingGlobalSortOrder() throws {
        let first = try useCase.createTask(title: "First", notes: "", status: .todo)
        let second = try useCase.createTask(title: "Second", notes: "", status: .done)
        XCTAssertLessThan(first.sortOrder, second.sortOrder, "sortOrder increments globally, independent of status")
    }

    func testUpdateTaskBumpsUpdatedAtAndMarksPending() throws {
        let created = try useCase.createTask(title: "Draft", notes: "")
        var synced = created
        synced.syncStatus = .synced
        try repository.upsert(synced)

        let updated = try useCase.updateTask(synced, title: "Final", notes: "done")
        XCTAssertEqual(updated.title, "Final")
        XCTAssertEqual(updated.syncStatus, .pendingUpload)
        XCTAssertGreaterThanOrEqual(updated.updatedAt, created.updatedAt)
    }

    func testUpdateTaskWithBlankTitleThrowsAndLeavesTaskUnchanged() throws {
        let created = try useCase.createTask(title: "Keep me", notes: "")
        XCTAssertThrowsError(try useCase.updateTask(created, title: "  ", notes: "x"))
        let stored = try repository.allTasks().first
        XCTAssertEqual(stored?.title, "Keep me")
    }

    func testDeleteTaskTombstonesRatherThanRemoving() throws {
        let created = try useCase.createTask(title: "Temp", notes: "")
        let deleted = try useCase.deleteTask(created)
        XCTAssertTrue(deleted.isDeleted)
        XCTAssertEqual(deleted.syncStatus, .pendingDelete)
        XCTAssertEqual(try repository.allTasks().count, 1, "task must still exist locally until the remote confirms the delete")
    }

    func testLoadBoardFiltersOutDeletedTasks() throws {
        let visible = try useCase.createTask(title: "Visible", notes: "")
        let removed = try useCase.createTask(title: "Removed", notes: "")
        _ = try useCase.deleteTask(removed)

        let board = try useCase.loadBoard()
        XCTAssertEqual(board.map(\.id), [visible.id])
    }

    func testRestoreTaskClearsTombstoneAndMarksPending() throws {
        let created = try useCase.createTask(title: "Undo me", notes: "")
        let deleted = try useCase.deleteTask(created)
        let restored = try useCase.restoreTask(deleted)

        XCTAssertFalse(restored.isDeleted)
        XCTAssertEqual(restored.syncStatus, .pendingUpload)
        XCTAssertEqual(try useCase.loadBoard().map(\.id), [created.id])
    }

    func testMoveTaskChangesStatusButNotPosition() throws {
        let task = try useCase.createTask(title: "Move me", notes: "", status: .todo)
        let originalOrder = task.sortOrder

        let moved = try useCase.moveTask(task, to: .inProgress)

        XCTAssertEqual(moved.status, .inProgress)
        XCTAssertEqual(moved.sortOrder, originalOrder, "changing status must not move the task within the global list")
    }

    func testMoveTaskToSameStatusIsNoOp() throws {
        let task = try useCase.createTask(title: "Stay put", notes: "", status: .todo)
        var synced = task
        synced.syncStatus = .synced
        try repository.upsert(synced)

        let result = try useCase.moveTask(synced, to: .todo)
        XCTAssertEqual(result.syncStatus, .synced, "a no-op move must not dirty an already-synced task")
    }

    func testReorderTasksReassignsGlobalOrderAcrossStatuses() throws {
        let first = try useCase.createTask(title: "First", notes: "", status: .todo)
        let second = try useCase.createTask(title: "Second", notes: "", status: .inProgress)
        let third = try useCase.createTask(title: "Third", notes: "", status: .done)

        try useCase.reorderTasks(orderedIDs: [third.id, first.id, second.id])

        let board = try useCase.loadBoard().sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(board.map(\.id), [third.id, first.id, second.id])
        XCTAssertTrue(board.allSatisfy { $0.syncStatus == .pendingUpload })
    }

    func testReorderTasksLeavesUnaffectedTaskUntouched() throws {
        let moving = try useCase.createTask(title: "Moving", notes: "")
        var settled = try useCase.createTask(title: "Already synced", notes: "")
        settled.syncStatus = .synced
        try repository.upsert(settled)

        // settled is already at its correct index (1), so reordering with it unchanged
        // shouldn't dirty it back to pending.
        try useCase.reorderTasks(orderedIDs: [moving.id, settled.id])

        let stored = try repository.allTasks().first { $0.id == settled.id }
        XCTAssertEqual(stored?.syncStatus, .synced)
    }
}
