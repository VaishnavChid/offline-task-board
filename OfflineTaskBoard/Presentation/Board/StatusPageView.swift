//
//  StatusPageView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

/// One tab's worth of the board: its own heading and tint, a list of floating task cards with
/// swipe-to-delete, and an Edit affordance for drag-to-reorder. Cross-status moves don't happen
/// here — they're buried in each card's "..." menu — since only one status is on screen at a time.
struct StatusPageView: View {
    let status: TaskStatus
    let tasks: [TaskItem]
    let onEdit: (TaskItem) -> Void
    let onDelete: (TaskItem) -> Void
    let onMove: (TaskItem, TaskStatus) -> Void
    let onReorder: (IndexSet, Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(status.title)
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(status.tintColor)
                Spacer()
                if !tasks.isEmpty {
                    EditButton()
                }
            }
            .padding(.horizontal)
            .padding(.top, 4)

            if tasks.isEmpty {
                ContentUnavailableView(
                    "No \(status.title) Tasks",
                    systemImage: status.symbolName,
                    description: Text("Tasks you add or move here will show up on this page.")
                )
                .frame(maxHeight: .infinity)
            } else {
                List {
                    ForEach(tasks) { task in
                        TaskCardView(
                            task: task,
                            onEdit: { onEdit(task) },
                            onDelete: { onDelete(task) },
                            onMove: { onMove(task, $0) }
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { onDelete(task) } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .onMove(perform: onReorder)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .tint(status.tintColor)
    }
}
