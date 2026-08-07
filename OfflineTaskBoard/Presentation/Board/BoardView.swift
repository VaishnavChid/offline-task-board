//
//  BoardView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

struct BoardView: View {
    @StateObject private var viewModel: BoardViewModel
    @State private var showingEditor = false
    @State private var editingTask: TaskItem?
    @State private var editMode: EditMode = .inactive

    init(viewModel: BoardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
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
                taskList
            }
        }
        .sheet(isPresented: $showingEditor) {
            TaskEditorView(task: editingTask) { title, notes in
                if let editingTask {
                    viewModel.updateTask(editingTask, title: title, notes: notes)
                } else {
                    viewModel.createTask(title: title, notes: notes, status: .todo)
                }
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .task {
            viewModel.load()
            await viewModel.syncNow()
        }
    }

    /// One flat list instead of grouping by status — a status with many tasks no longer buries
    /// the others further down the screen. Order is a single global `sortOrder` (drag to
    /// reorder via the toolbar button below); status is shown per-card via the tappable icon
    /// (advances the workflow) and the small badge on its second line, not by position.
    private var taskList: some View {
        List {
            ForEach(viewModel.tasks) { task in
                TaskCardView(
                    task: task,
                    onEdit: {
                        editingTask = task
                        showingEditor = true
                    },
                    onDelete: { viewModel.deleteTask(task) },
                    onMove: { destination in viewModel.moveTask(task, to: destination) },
                    onAdvanceStatus: { viewModel.advanceStatus(of: task) }
                )
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) { viewModel.deleteTask(task) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .tint(.red)
                }
            }
            .onMove { source, destination in
                viewModel.reorderTasks(source: source, destination: destination)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .environment(\.editMode, $editMode)
    }

    private var header: some View {
        HStack {
            Text("Task Board")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Spacer()
            Button {
                editMode = editMode == .active ? .inactive : .active
            } label: {
                Image(systemName: editMode == .active ? "checkmark.circle.fill" : "arrow.up.arrow.down.circle")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel(editMode == .active ? "Done reordering" : "Reorder tasks")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { viewModel.errorMessage != nil }, set: { if !$0 { viewModel.errorMessage = nil } })
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
            Spacer(minLength: 8)
            Button("Sync") { Task { await viewModel.syncNow() } }
                .font(.footnote.weight(.semibold))
                .disabled(viewModel.isSyncing)
        }
        .padding(12)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// Deliberately outside the sync card — adding a task and checking sync status are unrelated
    /// actions and shouldn't share one container.
    private var addTaskButton: some View {
        Button {
            editingTask = nil
            showingEditor = true
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
