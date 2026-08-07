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
    /// Consumed by the next `fetchAll()` call only — simulates a slow network read that resolves
    /// after other, faster work (like a concurrent sync's delete) has already run.
    private var nextFetchDelayNanoseconds: UInt64 = 0

    func stubFetch(_ tasks: [TaskItem]) { stubbedFetch = tasks }
    func failSaving(id: UUID) { failingIDs.insert(id) }
    func delayNextFetch(nanoseconds: UInt64) { nextFetchDelayNanoseconds = nanoseconds }

    func fetchAll() async throws -> [TaskItem] {
        let delay = nextFetchDelayNanoseconds
        nextFetchDelayNanoseconds = 0
        if delay > 0 {
            try await Task.sleep(nanoseconds: delay)
        }
        return stubbedFetch
    }

    func save(_ task: TaskItem) async throws {
        if failingIDs.contains(task.id) { throw RemoteDataSourceError.notConfigured }
        savedTasks.append(task)
    }

    func delete(id: UUID) async throws {
        deletedIDs.append(id)
        // A real backend reflects a completed delete on the very next fresh read — a stub that
        // stayed static here would let a later, non-delayed fetch see a document that a real
        // Firestore read wouldn't, which isn't the race this fake exists to model.
        stubbedFetch.removeAll { $0.id == id }
    }
}

struct ThrowingRemoteDataSource: TaskRemoteDataSource {
    func fetchAll() async throws -> [TaskItem] { throw RemoteDataSourceError.notConfigured }
    func save(_ task: TaskItem) async throws { throw RemoteDataSourceError.notConfigured }
    func delete(id: UUID) async throws { throw RemoteDataSourceError.notConfigured }
}
