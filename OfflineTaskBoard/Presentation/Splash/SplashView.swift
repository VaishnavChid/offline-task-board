//
//  SplashView.swift
//  OfflineTaskBoard
//
//  Created by Vaishnav on 07/08/26.
//

import SwiftUI

/// Shown by `RootView` while the initial load + sync are in flight. The gradient uses the same
/// three status tint colors as the board itself, so the very first thing a user sees already
/// hints at what the app is about.
struct SplashView: View {
    @State private var animateGradient = false

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground).ignoresSafeArea()

            LinearGradient(
                colors: [TaskStatus.todo.tintColor, TaskStatus.inProgress.tintColor, TaskStatus.done.tintColor],
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .opacity(0.28)
            .ignoresSafeArea()

            VStack(spacing: 14) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(.indigo)
                    .symbolEffect(.pulse, options: .repeating)

                Text("Task Board")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                animateGradient = true
            }
        }
    }
}
