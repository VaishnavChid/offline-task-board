//
//  TaskRemoteDataSource.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

/// The remote service boundary. `TaskSyncUseCase` only ever talks to this protocol, so it has no
/// idea whether the concrete implementation is Firestore, an offline stub, or a test fake.
protocol TaskRemoteDataSource: Sendable {
    func fetchAll() async throws -> [TaskItem]
    func save(_ task: TaskItem) async throws
    func delete(id: UUID) async throws
}

enum RemoteDataSourceError: LocalizedError {
    case notConfigured
    case decodingFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Cloud sync isn't set up yet. Your changes are saved on this device and will sync once it is."
        case .decodingFailed(let reason):
            return "A task from the cloud couldn't be read (\(reason))."
        }
    }
}
