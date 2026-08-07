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
    @State private var editorDefaultStatus: TaskStatus = .todo

    init(viewModel: BoardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [Color.indigo.opacity(0.16), Color.cyan.opacity(0.06), Color(uiColor: .systemBackground)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(spacing: 16) {
                    syncStatusBar
                        .padding(.horizontal)
                        .padding(.top, 8)

                    ScrollView(.horizontal) {
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(TaskStatus.allCases) { status in
                                TaskColumnView(
                                    status: status,
                                    tasks: viewModel.tasks(in: status),
                                    onEdit: { task in
                                        editingTask = task
                                        showingEditor = true
                                    },
                                    onDelete: { task in viewModel.deleteTask(task) },
                                    onMove: { task, destination in viewModel.moveTask(task, to: destination) },
                                    onDrop: { draggedID, destination, beforeID in
                                        viewModel.moveDraggedTask(id: draggedID, into: destination, before: beforeID)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 24)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Task Board")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingTask = nil
                        editorDefaultStatus = .todo
                        showingEditor = true
                    } label: {
                        Label("Add Task", systemImage: "plus")
                    }
                    .accessibilityLabel("Add task")
                }
            }
            .sheet(isPresented: $showingEditor) {
                TaskEditorView(task: editingTask) { title, notes in
                    if let editingTask {
                        viewModel.updateTask(editingTask, title: title, notes: notes)
                    } else {
                        viewModel.createTask(title: title, notes: notes, status: editorDefaultStatus)
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
            .refreshable {
                await viewModel.syncNow()
            }
        }
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
}
