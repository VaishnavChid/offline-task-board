//
//  TaskEditorView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

/// No dedicated view model — two text fields and a save action don't carry enough logic to
/// justify one. Validation (non-empty title) lives in `TaskEditingUseCase`, not here; this view
/// only disables Save as a UX nicety.
struct TaskEditorView: View {
    let task: TaskItem?
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var notes: String

    init(task: TaskItem?, onSave: @escaping (String, String) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Title", text: $title)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(task == nil ? "New Task" : "Edit Task")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, notes)
                        dismiss()
                    }
                    .tint(.blue)
                    .disabled(isTitleEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
    }

    private var isTitleEmpty: Bool {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
