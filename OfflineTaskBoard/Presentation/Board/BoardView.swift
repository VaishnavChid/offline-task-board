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
                syncStatusBar
                    .padding(.horizontal)

                TabView(selection: $viewModel.selectedStatus) {
                    ForEach(TaskStatus.allCases) { status in
                        Tab(status.title, systemImage: status.symbolName, value: status) {
                            StatusPageView(
                                status: status,
                                tasks: viewModel.tasks(in: status),
                                onEdit: { task in
                                    editingTask = task
                                    showingEditor = true
                                },
                                onDelete: { task in viewModel.deleteTask(task) },
                                onMove: { task, destination in viewModel.moveTask(task, to: destination) },
                                onReorder: { source, destination in
                                    viewModel.reorderCurrentTasks(source: source, destination: destination)
                                }
                            )
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingEditor) {
            TaskEditorView(task: editingTask) { title, notes in
                if let editingTask {
                    viewModel.updateTask(editingTask, title: title, notes: notes)
                } else {
                    viewModel.createTask(title: title, notes: notes, status: viewModel.selectedStatus)
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

    private var header: some View {
        HStack {
            Text("Task Board")
                .font(.system(size: 30, weight: .bold, design: .rounded))
            Spacer()
            Button {
                editingTask = nil
                showingEditor = true
            } label: {
                Label("Add Task", systemImage: "plus")
            }
            .accessibilityLabel("Add task")
        }
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
}
