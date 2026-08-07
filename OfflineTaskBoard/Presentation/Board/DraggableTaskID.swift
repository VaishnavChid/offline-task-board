//
//  DraggableTaskID.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI
import UniformTypeIdentifiers

/// What actually gets carried by `.draggable`/`.dropDestination` on the board. A thin wrapper
/// around just the id — not `TaskItem` itself — so this Presentation-only drag-and-drop concern
/// never leaks a `Transferable` conformance requirement onto the Domain entity.
struct DraggableTaskID: Codable, Transferable {
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .offlineTaskBoardTaskID)
    }
}

extension UTType {
    static var offlineTaskBoardTaskID: UTType {
        UTType(exportedAs: "com.vaishnav.OfflineTaskBoard.taskID")
    }
}
