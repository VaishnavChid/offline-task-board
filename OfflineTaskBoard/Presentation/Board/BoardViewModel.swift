//
//  BoardViewModel.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import Foundation

@MainActor
final class BoardViewModel: ObservableObject {
    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var syncSummaryMessage = "Not synced yet"
    @Published private(set) var isSyncing = false
    @Published var errorMessage: String?
    @Published var selectedStatus: TaskStatus = .todo

    private let editing: TaskEditingUseCase
    private let sync: TaskSyncUseCase

    init(editing: TaskEditingUseCase, sync: TaskSyncUseCase) {
        self.editing = editing
        self.sync = sync
    }

    func load() {
        do {
            tasks = try editing.loadBoard()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func tasks(in status: TaskStatus) -> [TaskItem] {
        tasks.filter { $0.status == status }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func createTask(title: String, notes: String, status: TaskStatus) {
        perform { try editing.createTask(title: title, notes: notes, status: status) }
    }

    func updateTask(_ task: TaskItem, title: String, notes: String) {
        perform { try editing.updateTask(task, title: title, notes: notes) }
    }

    func deleteTask(_ task: TaskItem) {
        perform { try editing.deleteTask(task) }
    }

    func moveTask(_ task: TaskItem, to status: TaskStatus) {
        perform { try editing.moveTask(task, to: status) }
    }

    /// List-driven reorder within whichever status tab is currently visible. `source`/`destination`
    /// come straight from SwiftUI's `.onMove`, so this is only ever a same-status reorder — moving
    /// a task to a different status happens through the "Move to" menu instead.
    func reorderCurrentTasks(source: IndexSet, destination: Int) {
        let current = tasks(in: selectedStatus)
        guard let sourceIndex = source.first, source.count == 1, sourceIndex < current.count else { return }
        var orderedIDs = current.map(\.id)
        orderedIDs.move(fromOffsets: source, toOffset: destination)
        let movedTask = current[sourceIndex]
        perform { try editing.placeTask(movedTask, in: selectedStatus, orderedIDs: orderedIDs) }
    }

    func syncNow() async {
        isSyncing = true
        let summary = await sync.sync()
        load()
        syncSummaryMessage = message(for: summary)
        isSyncing = false
    }

    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func message(for summary: SyncSummary) -> String {
        if summary.hasFailures {
            return "Some changes couldn't sync — they're saved and will retry"
        }
        if summary.conflicted > 0 {
            let word = summary.conflicted == 1 ? "conflict" : "conflicts"
            return "Synced — resolved \(summary.conflicted) \(word) in your favor"
        }
        if summary.uploaded == 0 && summary.pulled == 0 {
            return "Everything's already up to date"
        }
        return "All changes synced"
    }
}
