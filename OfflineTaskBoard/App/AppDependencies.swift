//
//  AppDependencies.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation
import SwiftData

/// The composition root: the one place concrete Data-layer types get wired into the Domain
/// protocols the rest of the app depends on. Nothing outside this file decides which remote
/// store is in play.
@MainActor
final class AppDependencies {
    let modelContainer: ModelContainer
    let repository: TaskRepository
    let remote: TaskRemoteDataSource
    let editing: TaskEditingUseCase
    let sync: TaskSyncUseCase

    init() {
        do {
            modelContainer = try ModelContainer(for: TaskModel.self)
        } catch {
            fatalError("Unable to create the local database: \(error.localizedDescription)")
        }

        repository = SwiftDataTaskRepository(context: modelContainer.mainContext)

        #if canImport(FirebaseFirestore)
        FirebaseBootstrap.configureIfAvailable()
        remote = FirebaseBootstrap.isConfigured ? FirestoreTaskRemoteStore() : UnavailableTaskRemoteStore()
        #else
        remote = UnavailableTaskRemoteStore()
        #endif

        editing = TaskEditingUseCase(repository: repository)
        sync = TaskSyncUseCase(repository: repository, remote: remote)
    }

    func makeBoardViewModel() -> BoardViewModel {
        BoardViewModel(editing: editing, sync: sync)
    }
}
