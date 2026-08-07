//
//  SyncStatus.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

/// Where a task stands relative to the remote service. Every local mutation moves a task
/// out of `.synced` immediately; only a confirmed round-trip through `TaskSyncUseCase` moves it back.
enum SyncStatus: String, Codable, Sendable {
    case synced
    case pendingUpload
    case pendingDelete
    case failed
    /// The remote copy changed since our last confirmed sync while we also had unsynced local
    /// edits. Local wins and is queued to overwrite the server on the next sync pass; this state
    /// exists purely so the UI can tell the user that happened instead of silently discarding a
    /// remote change.
    case conflicted
}
