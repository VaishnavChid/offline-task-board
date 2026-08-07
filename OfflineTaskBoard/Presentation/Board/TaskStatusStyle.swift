//
//  TaskStatusStyle.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

/// Presentation-only styling for `TaskStatus` — icon and tint per tab. Lives here rather than on
/// the entity itself so Domain never imports SwiftUI.
extension TaskStatus {
    var symbolName: String {
        switch self {
        case .todo: return "circle"
        case .inProgress: return "timer"
        case .done: return "checkmark.circle.fill"
        }
    }

    /// `.done` is gray rather than a status color — a finished task is deliberately deprioritized
    /// visually, not celebrated with color, since it also sinks to the bottom of the list.
    var tintColor: Color {
        switch self {
        case .todo: return .indigo
        case .inProgress: return .orange
        case .done: return .gray
        }
    }
}
