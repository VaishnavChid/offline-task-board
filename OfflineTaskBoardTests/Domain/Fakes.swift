//
//  Fakes.swift
//  OfflineTaskBoardTests
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation
@testable import OfflineTaskBoard

@MainActor
final class InMemoryTaskRepository: TaskRepository {
    private(set) var storage: [UUID: TaskItem] = [:]

    func allTasks() throws -> [TaskItem] { Array(storage.values) }
    func pendingTasks() throws -> [TaskItem] { storage.values.filter { $0.syncStatus != .synced } }
    func upsert(_ task: TaskItem) throws { storage[task.id] = task }
    func hardDelete(id: UUID) throws { storage[id] = nil }
}

/// Configurable fake remote used by the sync tests: records every save/delete, lets a test stub
/// what a fetch should return, and lets a test force specific tasks to fail on save.
actor RecordingRemoteDataSource: TaskRemoteDataSource {
    private(set) var savedTasks: [TaskItem] = []
    private(set) var deletedIDs: [UUID] = []
    private var stubbedFetch: [TaskItem] = []
    private var failingIDs: Set<UUID> = []

    func stubFetch(_ tasks: [TaskItem]) { stubbedFetch = tasks }
    func failSaving(id: UUID) { failingIDs.insert(id) }

    func fetchAll() async throws -> [TaskItem] { stubbedFetch }

    func save(_ task: TaskItem) async throws {
        if failingIDs.contains(task.id) { throw RemoteDataSourceError.notConfigured }
        savedTasks.append(task)
    }

    func delete(id: UUID) async throws {
        deletedIDs.append(id)
    }
}

struct ThrowingRemoteDataSource: TaskRemoteDataSource {
    func fetchAll() async throws -> [TaskItem] { throw RemoteDataSourceError.notConfigured }
    func save(_ task: TaskItem) async throws { throw RemoteDataSourceError.notConfigured }
    func delete(id: UUID) async throws { throw RemoteDataSourceError.notConfigured }
}
