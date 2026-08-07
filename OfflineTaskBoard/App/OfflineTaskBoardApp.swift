//
//  OfflineTaskBoardApp.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI
import SwiftData

@main
struct OfflineTaskBoardApp: App {
    private let dependencies = AppDependencies()

    var body: some Scene {
        WindowGroup {
            BoardView(viewModel: dependencies.makeBoardViewModel())
        }
        .modelContainer(dependencies.modelContainer)
    }
}
