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
            errorMessage = "Couldn't load your tasks. Try again in a moment."
        }
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

    /// The status icon on each card cycles forward through the workflow — todo -> inProgress ->
    /// done -> todo — so changing a task's state never requires opening the "..." menu at all.
    func advanceStatus(of task: TaskItem) {
        let all = TaskStatus.allCases
        guard let index = all.firstIndex(of: task.status) else { return }
        let next = all[(index + 1) % all.count]
        moveTask(task, to: next)
    }

    /// List-driven reorder of the whole flat board. `source`/`destination` come straight from
    /// SwiftUI's `.onMove` — `tasks` is already the global, sortOrder-driven display order, so
    /// this reorders across statuses exactly the same way as within one.
    func reorderTasks(source: IndexSet, destination: Int) {
        guard let sourceIndex = source.first, source.count == 1, sourceIndex < tasks.count else { return }
        var orderedIDs = tasks.map(\.id)
        orderedIDs.move(fromOffsets: source, toOffset: destination)
        perform { try editing.reorderTasks(orderedIDs: orderedIDs) }
    }

    func syncNow() async {
        isSyncing = true
        let summary = await sync.sync()
        load()
        syncSummaryMessage = message(for: summary)
        isSyncing = false
    }

    /// Surfaces our own `TaskValidationError` messages verbatim — they're written for the user
    /// already (e.g. "Give the task a title before saving"). Anything else is an unexpected
    /// failure in the storage layer; rather than showing its raw, technical description, this
    /// falls back to one honest, non-alarming message so the user always sees something they can
    /// actually act on instead of a SwiftData/Foundation error string.
    private func perform(_ action: () throws -> Void) {
        do {
            try action()
            load()
        } catch let validationError as TaskValidationError {
            errorMessage = validationError.errorDescription
        } catch {
            errorMessage = "Something went wrong saving that change. Your other tasks are safe."
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
