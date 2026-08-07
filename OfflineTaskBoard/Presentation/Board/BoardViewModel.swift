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

    /// Drag-and-drop lands here: `beforeID` is the card the dragged task was dropped on (insert
    /// before it), or `nil` when dropped in the column's empty trailing area (append to the end).
    /// Handles a same-column reorder and a cross-column move identically.
    func moveDraggedTask(id draggedID: UUID, into status: TaskStatus, before beforeID: UUID?) {
        guard let dragged = tasks.first(where: { $0.id == draggedID }) else { return }
        var columnIDs = tasks(in: status).filter { $0.id != draggedID }.map(\.id)
        if let beforeID, let index = columnIDs.firstIndex(of: beforeID) {
            columnIDs.insert(draggedID, at: index)
        } else {
            columnIDs.append(draggedID)
        }
        perform { try editing.placeTask(dragged, in: status, orderedIDs: columnIDs) }
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
