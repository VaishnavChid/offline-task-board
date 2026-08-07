//
//  UnavailableTaskRemoteStore.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

/// Used whenever Firestore isn't configured — no `GoogleService-Info.plist`, or the package
/// simply isn't resolved. The app stays fully usable offline either way: every write still lands
/// in SwiftData immediately, and `TaskSyncUseCase` surfaces "not configured" through the normal
/// failure path rather than crashing or silently dropping work. This is what makes committing
/// real Firebase credentials to the repo unnecessary.
struct UnavailableTaskRemoteStore: TaskRemoteDataSource {
    func fetchAll() async throws -> [TaskItem] { throw RemoteDataSourceError.notConfigured }
    func save(_ task: TaskItem) async throws { throw RemoteDataSourceError.notConfigured }
    func delete(id: UUID) async throws { throw RemoteDataSourceError.notConfigured }
}
