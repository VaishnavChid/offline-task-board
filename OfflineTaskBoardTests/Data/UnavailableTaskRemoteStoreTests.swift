//
//  UnavailableTaskRemoteStoreTests.swift
//  OfflineTaskBoardTests
//
//  Created by Vaishnav on 07/08/26.
//

import XCTest
@testable import OfflineTaskBoard

@MainActor
final class UnavailableTaskRemoteStoreTests: XCTestCase {
    func testAllOperationsThrowNotConfigured() async {
        let store = UnavailableTaskRemoteStore()

        await assertThrowsNotConfigured { try await store.fetchAll() }
        await assertThrowsNotConfigured { try await store.save(TaskItem(title: "x", status: .todo, sortOrder: 0)) }
        await assertThrowsNotConfigured { try await store.delete(id: UUID()) }
    }

    /// The point of this fallback: without any remote configured at all, a create-then-sync
    /// still leaves the task safely on the device rather than losing it.
    func testSyncingAgainstAnUnconfiguredRemoteKeepsTheTaskLocalAndMarksItFailed() async throws {
        let repository = InMemoryTaskRepository()
        let editing = TaskEditingUseCase(repository: repository)
        let sync = TaskSyncUseCase(repository: repository, remote: UnavailableTaskRemoteStore())

        let task = try editing.createTask(title: "Works offline", notes: "")
        let summary = await sync.sync()

        XCTAssertEqual(summary.failed, 1)
        let stored = try repository.allTasks().first
        XCTAssertEqual(stored?.id, task.id)
        XCTAssertEqual(stored?.syncStatus, .failed)
    }

    private func assertThrowsNotConfigured(_ operation: () async throws -> Void) async {
        do {
            try await operation()
            XCTFail("expected RemoteDataSourceError.notConfigured")
        } catch RemoteDataSourceError.notConfigured {
            // expected
        } catch {
            XCTFail("expected notConfigured, got \(error)")
        }
    }
}
