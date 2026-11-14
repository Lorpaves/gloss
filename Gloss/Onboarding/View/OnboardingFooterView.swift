//
//  OnboardingFooterView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import SwiftUI

/// The guide's footer, which stays put while the pages slide: where the guide is, and the buttons to move on.
internal struct OnboardingFooterView: View {
    // MARK: - Properties

    internal var viewModel: OnboardingViewModel

    // MARK: - Body

    internal var body: some View {
        HStack(spacing: 12) {
            PageDots(count: viewModel.steps.count, current: viewModel.stepIndex)
            Spacer()
            if viewModel.canGoBack, viewModel.step != .finish {
                Button("返回") {
                    viewModel.back()
                }
                .controlSize(.large)
            }
            primaryButton
                .controlSize(.large)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // The footer is always on screen, so it watches for the permission the current page asks for.
        .onChange(of: viewModel.accessibility.isTrusted) { _, isTrusted in
            if isTrusted, viewModel.step == .accessibility {
                viewModel.permissionWasGranted()
            }
        }
        .onChange(of: viewModel.clipboard.isAllowed) { _, isAllowed in
            if isAllowed, viewModel.step == .clipboard {
                viewModel.permissionWasGranted()
            }
        }
    }

    // MARK: - Private

    @ViewBuilder
    private var primaryButton: some View {
        switch viewModel.step {
        case .welcome:
            prominentButton("开始")
        case .accessibility:
            viewModel.accessibility.isTrusted ? AnyView(prominentButton("继续")) : AnyView(plainButton("稍后"))
        case .clipboard:
            viewModel.clipboard.isAllowed ? AnyView(prominentButton("继续")) : AnyView(plainButton("跳过"))
        case .model:
            viewModel.model.needsDownload ? AnyView(plainButton("稍后")) : AnyView(prominentButton("继续"))
        case .finish:
            prominentButton("完成")
        }
    }

    private func prominentButton(_ title: LocalizedStringKey) -> some View {
        Button(title) {
            viewModel.next()
        }
        .buttonStyle(.borderedProminent)
        .keyboardShortcut(.defaultAction)
    }

    private func plainButton(_ title: LocalizedStringKey) -> some View {
        Button(title) {
            viewModel.next()
        }
    }
}

// MARK: - PageDots

/// Which page of how many is showing.
private struct PageDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == current ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: index == current ? 16 : 7, height: 7)
            }
        }
        .animation(.smooth(duration: 0.3), value: current)
        .accessibilityElement()
        .accessibilityLabel(Text("第 \(current + 1) 页，共 \(count) 页"))
    }
}
