//
//  RootView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

/// Owns the app's one `BoardViewModel` and gates `BoardView` behind `SplashView` until the
/// initial load + sync finish, so the splash is genuinely tied to startup work rather than
/// shown for a fixed, arbitrary duration.
struct RootView: View {
    @StateObject private var viewModel: BoardViewModel
    @State private var isReady = false

    init(viewModel: BoardViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        ZStack {
            if isReady {
                BoardView(viewModel: viewModel)
                    .transition(.opacity)
            } else {
                SplashView()
                    .transition(.opacity)
            }
        }
        .task {
            viewModel.load()
            await viewModel.syncNow()
            withAnimation(.easeInOut(duration: 0.4)) {
                isReady = true
            }
        }
    }
}
