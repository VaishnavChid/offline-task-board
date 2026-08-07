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

    func testCreateTaskAssignsIncrementingSortOrderWithinColumn() throws {
        let first = try useCase.createTask(title: "First", notes: "")
        let second = try useCase.createTask(title: "Second", notes: "")
        XCTAssertLessThan(first.sortOrder, second.sortOrder)
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

    func testMoveTaskAppendsToEndOfDestinationColumn() throws {
        _ = try useCase.createTask(title: "Already in progress", notes: "", status: .inProgress)
        let task = try useCase.createTask(title: "Move me", notes: "", status: .todo)

        let moved = try useCase.moveTask(task, to: .inProgress)
        let column = try useCase.loadBoard().filter { $0.status == .inProgress }.sorted { $0.sortOrder < $1.sortOrder }

        XCTAssertEqual(moved.status, .inProgress)
        XCTAssertEqual(column.last?.id, moved.id)
    }

    func testMoveTaskToSameStatusIsNoOp() throws {
        let task = try useCase.createTask(title: "Stay put", notes: "", status: .todo)
        var synced = task
        synced.syncStatus = .synced
        try repository.upsert(synced)

        let result = try useCase.moveTask(synced, to: .todo)
        XCTAssertEqual(result.syncStatus, .synced, "a no-op move must not dirty an already-synced task")
    }

    func testPlaceTaskReordersWithinSameColumn() throws {
        let first = try useCase.createTask(title: "First", notes: "", status: .todo)
        let second = try useCase.createTask(title: "Second", notes: "", status: .todo)
        let third = try useCase.createTask(title: "Third", notes: "", status: .todo)

        try useCase.placeTask(first, in: .todo, orderedIDs: [second.id, third.id, first.id])

        let column = try useCase.loadBoard().filter { $0.status == .todo }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(column.map(\.id), [second.id, third.id, first.id])
        XCTAssertTrue(column.allSatisfy { $0.syncStatus == .pendingUpload })
    }

    func testPlaceTaskMovesAcrossColumnsAtExactPosition() throws {
        let inProgressA = try useCase.createTask(title: "A", notes: "", status: .inProgress)
        let inProgressB = try useCase.createTask(title: "B", notes: "", status: .inProgress)
        let moving = try useCase.createTask(title: "Moving", notes: "", status: .todo)

        try useCase.placeTask(moving, in: .inProgress, orderedIDs: [inProgressA.id, moving.id, inProgressB.id])

        let column = try useCase.loadBoard().filter { $0.status == .inProgress }.sorted { $0.sortOrder < $1.sortOrder }
        XCTAssertEqual(column.map(\.id), [inProgressA.id, moving.id, inProgressB.id])
    }
}
