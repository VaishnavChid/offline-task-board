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
/// change status, and reorder. Grouped into one type rather than one class per verb — a single
/// board entity doesn't have enough distinct business logic per action to justify separate
/// classes, and every one of these does the same three things (validate, stamp `updatedAt`, mark
/// `.pendingUpload`/`.pendingDelete`) before persisting.
///
/// `sortOrder` is a single global ordering across every task regardless of status — the board is
/// one list, not per-status columns, so status only changes which icon/badge a card shows, never
/// where it sits in that list.
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
            sortOrder: try nextSortOrder()
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

    /// Changes status only — position in the global list is untouched. Since the board is one
    /// flat list rather than per-status columns, moving to a different status shouldn't make a
    /// task jump to a different spot in it.
    @discardableResult
    func moveTask(_ task: TaskItem, to status: TaskStatus) throws -> TaskItem {
        guard task.status != status else { return task }
        var moved = task
        moved.status = status
        moved.updatedAt = .now
        moved.syncStatus = .pendingUpload
        try repository.upsert(moved)
        return moved
    }

    /// Reassigns `sortOrder` to match `orderedIDs` — the desired order for every currently
    /// visible (non-deleted) task, regardless of status. Drives manual drag-to-reorder.
    func reorderTasks(orderedIDs: [UUID]) throws {
        let byID = Dictionary(
            uniqueKeysWithValues: try repository.allTasks().filter { !$0.isDeleted }.map { ($0.id, $0) }
        )
        for (index, id) in orderedIDs.enumerated() {
            guard var task = byID[id], task.sortOrder != Double(index) else { continue }
            task.sortOrder = Double(index)
            task.updatedAt = .now
            task.syncStatus = .pendingUpload
            try repository.upsert(task)
        }
    }

    private func nextSortOrder() throws -> Double {
        let maxOrder = try repository.allTasks()
            .filter { !$0.isDeleted }
            .map(\.sortOrder)
            .max()
        return (maxOrder ?? -1) + 1
    }
}
