//
//  BoardView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

struct BoardView: View {
    /// Owned by `RootView`, which created it before the board was ever shown — this view only
    /// observes it.
    @ObservedObject var viewModel: BoardViewModel
    @State private var editorTarget: EditorTarget?
    @State private var editMode: EditMode = .inactive
    @State private var searchText = ""
    @State private var taskPendingDeletion: TaskItem?
    @FocusState private var isSearchFocused: Bool

    /// Drives `.sheet(item:)` rather than `.sheet(isPresented:)` + a separate `TaskItem?`: setting
    /// both a boolean and the task in the same action left the sheet's content occasionally
    /// presenting before it saw the task, always opening a blank "New Task" form even when editing
    /// an existing one. Keying presentation off one `Identifiable` value sidesteps that entirely.
    private enum EditorTarget: Identifiable {
        case create
        case edit(TaskItem)

        var id: String {
            switch self {
            case .create: return "create"
            case .edit(let task): return task.id.uuidString
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.indigo.opacity(0.16), Color.cyan.opacity(0.06), Color(uiColor: .systemBackground)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                header
                HStack(spacing: 12) {
                    syncStatusBar
                    addTaskButton
                }
                .padding(.horizontal)
                .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
                searchField
                taskList
            }
        }
        .onChange(of: searchText) { _, newValue in
            if !newValue.isEmpty { editMode = .inactive }
        }
        .sheet(item: $editorTarget) { target in
            switch target {
            case .create:
                TaskEditorView(task: nil) { title, notes in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.createTask(title: title, notes: notes, status: .todo)
                    }
                }
            case .edit(let task):
                TaskEditorView(task: task) { title, notes in
                    viewModel.updateTask(task, title: title, notes: notes)
                }
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .alert(
            "Delete \u{201C}\(taskPendingDeletion?.title ?? "")\u{201D}?",
            isPresented: deletionBinding
        ) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let task = taskPendingDeletion {
                    deleteWithAnimation(task)
                }
            }
        }
    }

    /// One flat list instead of grouping by status — a status with many tasks no longer buries
    /// the others further down the screen. Order is a single global `sortOrder` (drag to
    /// reorder via the toolbar button below); status is shown per-card via the tappable icon
    /// (advances the workflow) and the small badge on its second line, not by position.
    private var taskList: some View {
        List {
            if displayedTasks.isEmpty && !searchText.isEmpty {
                Text("No tasks match \u{201C}\(searchText)\u{201D}")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            ForEach(displayedTasks) { task in
                TaskCardView(
                    task: task,
                    onEdit: { editorTarget = .edit(task) },
                    onDelete: { taskPendingDeletion = task },
                    onMove: { destination in viewModel.moveTask(task, to: destination) },
                    onAdvanceStatus: { withAnimation(.easeInOut(duration: 0.2)) { viewModel.advanceStatus(of: task) } }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { taskPendingDeletion = task } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
            .onMove { source, destination in
                // Reordering is disabled while searching (see `header`, which hides the toggle) —
                // dragging a filtered subset isn't a meaningful position to persist. Otherwise
                // `displayedTasks`' exact current order (done tasks already sunk to the bottom)
                // is what actually gets persisted, not the raw `viewModel.tasks` order.
                guard searchText.isEmpty else { return }
                viewModel.reorderTasks(displayedIDs: displayedTasks.map(\.id), source: source, destination: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .animation(.easeInOut(duration: 0.25), value: viewModel.tasks)
        .environment(\.editMode, $editMode)
        // A TextField doesn't resign focus just because the user taps something else — without
        // this, the search field's cursor/keyboard stayed active (and could steal the next tap)
        // even while editing, deleting, or reordering a task. `simultaneousGesture` lets this
        // fire alongside whatever the tapped row/button already does, rather than intercepting it.
        .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
    }

    /// Search-filtered, then a stable partition that sinks `.done` tasks to the bottom without
    /// disturbing relative order otherwise — a display-time transform, not a change to the
    /// persisted `sortOrder`, so it stays purely presentational the same way search does.
    private var displayedTasks: [TaskItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = query.isEmpty ? viewModel.tasks : viewModel.tasks.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.notes.localizedCaseInsensitiveContains(query)
        }
        let active = base.filter { $0.status != .done }
        let done = base.filter { $0.status == .done }
        return active + done
    }

    /// Sits below the sync card and above the list — a plain filter over already-loaded tasks,
    /// not a use case: it's presentation-only, not a business rule.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search tasks", text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .focused($isSearchFocused)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal)
    }

    private func deleteWithAnimation(_ task: TaskItem) {
        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.deleteTask(task)
        }
    }

    private var header: some View {
        HStack {
            Text("Task Board")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Spacer()
            // Reordering is index-based against the unfiltered list — hidden while searching
            // rather than left available and silently wrong against filtered positions.
            if searchText.isEmpty {
                Button {
                    editMode = editMode == .active ? .inactive : .active
                } label: {
                    Image(systemName: editMode == .active ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(editMode == .active ? "Done reordering" : "Reorder tasks")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
        .simultaneousGesture(TapGesture().onEnded { isSearchFocused = false })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
    }

    private var deletionBinding: Binding<Bool> {
        Binding(get: { taskPendingDeletion != nil }, set: { if !$0 { taskPendingDeletion = nil } })
    }

    private var syncStatusBar: some View {
        HStack(spacing: 10) {
            if viewModel.isSyncing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "checkmark.icloud").foregroundStyle(.secondary)
            }
            Text(viewModel.syncSummaryMessage)
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .contentTransition(.opacity)
            Spacer(minLength: 8)
            Button("Sync") { Task { await viewModel.syncNow() } }
                .font(.footnote.weight(.semibold))
                .disabled(viewModel.isSyncing)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.2), value: viewModel.isSyncing)
        .animation(.easeInOut(duration: 0.2), value: viewModel.syncSummaryMessage)
    }

    /// Deliberately outside the sync card — adding a task and checking sync status are unrelated
    /// actions and shouldn't share one container.
    private var addTaskButton: some View {
        Button {
            editorTarget = .create
        } label: {
            Image(systemName: "plus")
                .font(.headline.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Color.blue, in: Circle())
        }
        .accessibilityLabel("Add task")
    }
}
