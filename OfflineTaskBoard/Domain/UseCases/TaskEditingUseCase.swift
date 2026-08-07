//
//  TaskEditingUseCase.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

enum TaskValidationError: LocalizedError {
    case emptyTitle

    var errorDescription: String? {
        switch self {
        case .emptyTitle: return "Give the task a title before saving."
        }
    }
}

/// Every mutation a user can make to a task: create, edit, delete (soft), restore (undo),
/// move between columns, and reorder within a column. Grouped into one type rather than one
/// class per verb — a single board entity doesn't have enough distinct business logic per
/// action to justify eight separate classes, and every one of these does the same three things
/// (validate, stamp `updatedAt`, mark `.pendingUpload`/`.pendingDelete`) before persisting.
@MainActor
final class TaskEditingUseCase {
    private let repository: TaskRepository

    init(repository: TaskRepository) {
        self.repository = repository
    }

    func loadBoard() throws -> [TaskItem] {
        try repository.allTasks().filter { !$0.isDeleted }
    }

    @discardableResult
    func createTask(title: String, notes: String, status: TaskStatus = .todo) throws -> TaskItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw TaskValidationError.emptyTitle }
        let task = TaskItem(
            title: trimmedTitle,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            status: status,
            sortOrder: try nextSortOrder(in: status)
        )
        try repository.upsert(task)
        return task
    }

    @discardableResult
    func updateTask(_ task: TaskItem, title: String, notes: String) throws -> TaskItem {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { throw TaskValidationError.emptyTitle }
        var updated = task
        updated.title = trimmedTitle
        updated.notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.updatedAt = .now
        updated.syncStatus = .pendingUpload
        try repository.upsert(updated)
        return updated
    }

    /// Soft-delete: the task is tombstoned, not removed, so `restoreTask` can undo it and the
    /// sync engine can still tell the remote it's gone.
    @discardableResult
    func deleteTask(_ task: TaskItem) throws -> TaskItem {
        var deleted = task
        deleted.isDeleted = true
        deleted.updatedAt = .now
        deleted.syncStatus = .pendingDelete
        try repository.upsert(deleted)
        return deleted
    }

    @discardableResult
    func restoreTask(_ task: TaskItem) throws -> TaskItem {
        var restored = task
        restored.isDeleted = false
        restored.updatedAt = .now
        restored.syncStatus = .pendingUpload
        try repository.upsert(restored)
        return restored
    }

    /// Menu-driven move (no explicit target position): appends to the end of the destination
    /// column. Drag-and-drop uses `placeTask` instead, which controls exact position.
    @discardableResult
    func moveTask(_ task: TaskItem, to status: TaskStatus) throws -> TaskItem {
        guard task.status != status else { return task }
        var moved = task
        moved.status = status
        moved.sortOrder = try nextSortOrder(in: status)
        moved.updatedAt = .now
        moved.syncStatus = .pendingUpload
        try repository.upsert(moved)
        return moved
    }

    /// Drag-and-drop move + reorder in one operation: places `task` into `status` at the
    /// position implied by `orderedIDs` (the desired final order of that column, including
    /// `task.id`), and reassigns sequential `sortOrder` to every task named in it. Handles a
    /// same-column reorder just as well as a cross-column move — the caller doesn't need to
    /// know which one it's doing.
    func placeTask(_ task: TaskItem, in status: TaskStatus, orderedIDs: [UUID]) throws {
        let targetIndex = orderedIDs.firstIndex(of: task.id) ?? orderedIDs.count
        var moved = task
        moved.status = status
        moved.sortOrder = Double(targetIndex)
        moved.updatedAt = .now
        moved.syncStatus = .pendingUpload
        try repository.upsert(moved)

        let restOfColumn = try repository.allTasks()
            .filter { $0.id != task.id && $0.status == status && !$0.isDeleted }
        let byID = Dictionary(uniqueKeysWithValues: restOfColumn.map { ($0.id, $0) })

        for (index, id) in orderedIDs.enumerated() where id != task.id {
            guard var item = byID[id], item.sortOrder != Double(index) else { continue }
            item.sortOrder = Double(index)
            item.updatedAt = .now
            item.syncStatus = .pendingUpload
            try repository.upsert(item)
        }
    }

    private func nextSortOrder(in status: TaskStatus) throws -> Double {
        let maxOrder = try repository.allTasks()
            .filter { $0.status == status && !$0.isDeleted }
            .map(\.sortOrder)
            .max()
        return (maxOrder ?? -1) + 1
    }
}
