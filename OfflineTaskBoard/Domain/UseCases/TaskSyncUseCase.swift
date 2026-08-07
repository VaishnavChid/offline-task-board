//
//  TaskSyncUseCase.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

struct SyncSummary: Equatable {
    var uploaded = 0
    var pulled = 0
    var conflicted = 0
    var failed = 0

    var hasFailures: Bool { failed > 0 }
}

/// Orchestrates local <-> remote sync and the conflict policy. This is pure business logic —
/// it only depends on the two Domain protocols, never on SwiftData or Firestore — so it's fully
/// unit-testable with fakes for both, and the concrete Data-layer implementations are just
/// interchangeable plumbing behind it.
@MainActor
final class TaskSyncUseCase {
    private let repository: TaskRepository
    private let remote: TaskRemoteDataSource

    init(repository: TaskRepository, remote: TaskRemoteDataSource) {
        self.repository = repository
        self.remote = remote
    }

    /// Pulls remote state and applies the conflict policy *before* draining the outbox. Pushing
    /// first would let a pending local edit blindly overwrite the server with an unconditional
    /// `setData` — with no read-before-write, nothing would ever notice a concurrent remote edit,
    /// so a genuine conflict could never actually be detected, only silently clobbered. Pulling
    /// first lets a pending local task be flagged `.conflicted` before it's pushed; the outbox
    /// drain that follows still pushes it — local still wins immediately, exactly as designed —
    /// but now the conflict was actually observed, not just overwritten in the dark.
    ///
    /// Each pending task is pushed independently: one task failing must never block the rest of
    /// the outbox from syncing (the bug this replaces let a single failure abort the whole batch).
    @discardableResult
    func sync() async -> SyncSummary {
        var summary = SyncSummary()
        await pullRemote(into: &summary)
        await drainOutbox(into: &summary)
        return summary
    }

    private func drainOutbox(into summary: inout SyncSummary) async {
        guard let pending = try? repository.pendingTasks() else { return }

        for task in pending {
            do {
                if task.isDeleted {
                    try await remote.delete(id: task.id)
                    try repository.hardDelete(id: task.id)
                } else {
                    try await remote.save(task)
                    var acknowledged = task
                    acknowledged.syncStatus = .synced
                    acknowledged.lastSyncedUpdatedAt = task.updatedAt
                    try repository.upsert(acknowledged)
                }
                summary.uploaded += 1
            } catch {
                var failedTask = task
                failedTask.syncStatus = .failed
                try? repository.upsert(failedTask)
                summary.failed += 1
            }
        }
    }

    private func pullRemote(into summary: inout SyncSummary) async {
        guard let remoteTasks = try? await remote.fetchAll(),
              let localTasks = try? repository.allTasks() else { return }

        let localByID = Dictionary(uniqueKeysWithValues: localTasks.map { ($0.id, $0) })

        for remoteTask in remoteTasks {
            guard let local = localByID[remoteTask.id] else {
                try? repository.upsert(remoteTask)
                summary.pulled += 1
                continue
            }

            // A pending delete always wins outright, regardless of what changed remotely in the
            // meantime — an in-flight deletion shouldn't be resurrected by an incoming edit.
            guard local.syncStatus != .pendingDelete else { continue }

            let baseline = local.lastSyncedUpdatedAt
            let remoteChangedSinceBaseline = baseline.map { remoteTask.updatedAt > $0 } ?? (remoteTask.updatedAt > local.updatedAt)
            guard remoteChangedSinceBaseline else { continue }

            // Local counts as "changed since baseline" either because its own timestamp has
            // moved past the last confirmed sync, or — the common real case — because it simply
            // has unsynced local work right now (`.pendingUpload`/`.failed`/already `.conflicted`).
            let localChangedSinceBaseline = local.syncStatus != .synced || (baseline.map { local.updatedAt > $0 } ?? false)
            if localChangedSinceBaseline {
                // Both sides changed since the last confirmed sync: a genuine conflict. Local
                // wins and gets queued (via `.conflicted`, which counts as pending) — the outbox
                // drain right after this pushes it, so the conflict resolves within this same
                // sync pass, not a future one — but the UI can still show the user it happened.
                var conflicted = local
                conflicted.syncStatus = .conflicted
                try? repository.upsert(conflicted)
                summary.conflicted += 1
            } else {
                var pulled = remoteTask
                pulled.syncStatus = .synced
                pulled.lastSyncedUpdatedAt = remoteTask.updatedAt
                try? repository.upsert(pulled)
                summary.pulled += 1
            }
        }
    }
}
