//
//  TaskRepository.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

/// The only interface Presentation and the use cases know about for local storage. Data provides
/// the concrete SwiftData-backed implementation; tests provide an in-memory fake. Neither the
/// use cases nor the view models ever import SwiftData directly.
@MainActor
protocol TaskRepository {
    func allTasks() throws -> [TaskItem]
    /// Every task whose `syncStatus` is not `.synced` — the outbox `TaskSyncUseCase` drains.
    func pendingTasks() throws -> [TaskItem]
    func upsert(_ task: TaskItem) throws
    /// Physically removes a task. Only ever called after a delete has been confirmed by the
    /// remote (or when the remote isn't configured at all, so there's nothing to confirm).
    func hardDelete(id: UUID) throws
}
