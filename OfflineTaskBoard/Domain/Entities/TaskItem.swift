//
//  TaskItem.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

/// The board's core entity. Deliberately named `TaskItem` rather than `Task` to avoid colliding
/// with `_Concurrency.Task`. Framework-independent by design: no SwiftData or Firestore imports
/// here, so business rules that operate on it are testable without either.
struct TaskItem: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var title: String
    var notes: String
    var status: TaskStatus
    /// Position within its status column. A plain ascending index reassigned on every
    /// create/move/reorder — see TaskEditingUseCase for why a fractional-index scheme wasn't
    /// worth the added complexity at this scale.
    var sortOrder: Double
    let createdAt: Date
    var updatedAt: Date
    var syncStatus: SyncStatus
    /// Soft-delete tombstone. A deleted task stays in local storage — filtered out of the board —
    /// until the remote delete is confirmed, so an offline delete is never lost and can be undone.
    var isDeleted: Bool
    /// The remote `updatedAt` as of the last confirmed sync. Used as the baseline to distinguish
    /// "remote changed" from "remote and local both changed" (a real conflict) during a pull.
    var lastSyncedUpdatedAt: Date?

    init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        status: TaskStatus = .todo,
        sortOrder: Double = 0,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        syncStatus: SyncStatus = .pendingUpload,
        isDeleted: Bool = false,
        lastSyncedUpdatedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.status = status
        self.sortOrder = sortOrder
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.syncStatus = syncStatus
        self.isDeleted = isDeleted
        self.lastSyncedUpdatedAt = lastSyncedUpdatedAt
    }
}
