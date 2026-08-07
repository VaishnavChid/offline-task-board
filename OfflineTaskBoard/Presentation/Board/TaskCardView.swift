//
//  TaskCardView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

struct TaskCardView: View {
    let task: TaskItem
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onMove: (TaskStatus) -> Void
    let onAdvanceStatus: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onAdvanceStatus) {
                Image(systemName: task.status.symbolName)
                    .font(.title2)
                    .foregroundStyle(task.status.tintColor)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Status: \(task.status.title)")
            .accessibilityHint("Double tap to advance to the next status")

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    Text(task.title)
                        .font(.headline)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Menu {
                        Section("Move to") {
                            ForEach(TaskStatus.allCases.filter { $0 != task.status }) { status in
                                Button(status.title) { onMove(status) }
                            }
                        }
                        Button("Edit", systemImage: "pencil", action: onEdit)
                        Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .accessibilityLabel("Task options")
                }

                HStack {
                    Text("Added \(addedDateText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: task.status.symbolName)
                        .font(.caption)
                        .foregroundStyle(task.status.tintColor)
                }

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }

                syncBadge
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.tint(task.status.tintColor.opacity(0.10)).interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture(perform: onEdit)
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: "Edit", onEdit)
        .accessibilityAction(named: "Delete", onDelete)
    }

    private var addedDateText: String {
        task.createdAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var syncBadge: some View {
        Label(syncLabel, systemImage: syncIcon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(syncTint)
    }

    private var syncLabel: String {
        switch task.syncStatus {
        case .synced: return "Synced"
        case .pendingUpload, .pendingDelete: return "Pending sync"
        case .failed: return "Failed to sync"
        case .conflicted: return "Kept your edit"
        }
    }

    private var syncIcon: String {
        switch task.syncStatus {
        case .synced: return "checkmark.icloud.fill"
        case .pendingUpload, .pendingDelete: return "icloud.and.arrow.up"
        case .failed: return "exclamationmark.icloud.fill"
        case .conflicted: return "arrow.triangle.branch"
        }
    }

    private var syncTint: Color {
        switch task.syncStatus {
        case .synced: return .green
        case .pendingUpload, .pendingDelete: return .orange
        case .failed: return .red
        case .conflicted: return .purple
        }
    }
}
