//
//  TaskColumnView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

struct TaskColumnView: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onMove: (TaskItem, TaskStatus) -> Void
    /// `beforeID` is nil when the drop landed in the column's empty trailing area.
    let onDrop: (_ draggedID: UUID, _ destination: TaskStatus, _ beforeID: UUID?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if tasks.isEmpty {
                EmptyColumnView(status: status)
                    .dropDestination(for: DraggableTaskID.self) { items, _ in
                        guard let dragged = items.first else { return false }
                        onDrop(dragged.id, status, nil)
                        return true
                    }
            } else {
                VStack(spacing: 10) {
                    ForEach(tasks) { task in
                        TaskCardView(
                            task: task,
                            onEdit: { onEdit(task) },
                            onDelete: { onDelete(task) },
                            onMove: { onMove(task, $0) }
                        )
                        .draggable(DraggableTaskID(id: task.id))
                        .dropDestination(for: DraggableTaskID.self) { items, _ in
                            guard let dragged = items.first, dragged.id != task.id else { return false }
                            onDrop(dragged.id, status, task.id)
                            return true
                        }
                    }

                    Color.clear
                        .frame(height: 44)
                        .dropDestination(for: DraggableTaskID.self) { items, _ in
                            guard let dragged = items.first else { return false }
                            onDrop(dragged.id, status, nil)
                            return true
                        }
                }
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .top)
        .glassEffect(.regular.tint(tint.opacity(0.06)), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(status.title).font(.title3.weight(.bold))
            Text("\(tasks.count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(tint.opacity(0.15), in: Capsule())
            Spacer()
        }
    }

    private var icon: String {
        switch status {
        case .todo: return "circle"
        case .inProgress: return "timer"
        case .done: return "checkmark.circle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .todo: return .indigo
        case .inProgress: return .orange
        case .done: return .green
        }
    }
}

private struct EmptyColumnView: View {
    let status: TaskStatus

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray").font(.title2).foregroundStyle(.tertiary)
            Text("No tasks yet").font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 140)
    }
}
