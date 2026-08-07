//
//  TaskModel.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation
import SwiftData

/// SwiftData's on-disk representation of a task. Kept separate from `TaskItem` on purpose: this
/// type may only ever be touched from `SwiftDataTaskRepository` — nothing above the Data layer
/// imports SwiftData, so swapping local storage later wouldn't ripple past this one file.
@Model
final class TaskModel {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var statusRaw: String
    var sortOrder: Double
    var createdAt: Date
    var updatedAt: Date
    var syncStatusRaw: String
    var isDeleted: Bool
    var lastSyncedUpdatedAt: Date?

    init(item: TaskItem) {
        id = item.id
        title = item.title
        notes = item.notes
        statusRaw = item.status.rawValue
        sortOrder = item.sortOrder
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        syncStatusRaw = item.syncStatus.rawValue
        isDeleted = item.isDeleted
        lastSyncedUpdatedAt = item.lastSyncedUpdatedAt
    }

    var asTaskItem: TaskItem {
        TaskItem(
            id: id,
            title: title,
            notes: notes,
            status: TaskStatus(rawValue: statusRaw) ?? .todo,
            sortOrder: sortOrder,
            createdAt: createdAt,
            updatedAt: updatedAt,
            syncStatus: SyncStatus(rawValue: syncStatusRaw) ?? .pendingUpload,
            isDeleted: isDeleted,
            lastSyncedUpdatedAt: lastSyncedUpdatedAt
        )
    }

    func apply(_ item: TaskItem) {
        title = item.title
        notes = item.notes
        statusRaw = item.status.rawValue
        sortOrder = item.sortOrder
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        syncStatusRaw = item.syncStatus.rawValue
        isDeleted = item.isDeleted
        lastSyncedUpdatedAt = item.lastSyncedUpdatedAt
    }
}
