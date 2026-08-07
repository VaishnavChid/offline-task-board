//
//  SwiftDataTaskRepository.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation
import SwiftData

/// The only file in the app that knows both `TaskItem` and `TaskModel` exist. Everything else —
/// the use cases, the view models — depends on `TaskRepository` and has no idea SwiftData is
/// the thing behind it.
@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func allTasks() throws -> [TaskItem] {
        try context
            .fetch(FetchDescriptor<TaskModel>(sortBy: [SortDescriptor(\.sortOrder)]))
            .map(\.asTaskItem)
    }

    func pendingTasks() throws -> [TaskItem] {
        try context
            .fetch(FetchDescriptor<TaskModel>())
            .map(\.asTaskItem)
            .filter { $0.syncStatus != .synced }
    }

    func upsert(_ task: TaskItem) throws {
        let id = task.id
        let descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
        if let existing = try context.fetch(descriptor).first {
            existing.apply(task)
        } else {
            context.insert(TaskModel(item: task))
        }
        try context.save()
    }

    func hardDelete(id: UUID) throws {
        let descriptor = FetchDescriptor<TaskModel>(predicate: #Predicate { $0.id == id })
        guard let existing = try context.fetch(descriptor).first else { return }
        context.delete(existing)
        try context.save()
    }
}
