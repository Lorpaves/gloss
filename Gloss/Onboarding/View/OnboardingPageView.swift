//
//  OnboardingPageView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import SwiftUI
import AppKit

/// One page of the welcome guide; ``OnboardingViewController`` slides between them.
internal struct OnboardingPageView: View {
    // MARK: - Properties

    internal let step: OnboardingStep
    internal var viewModel: OnboardingViewModel

    /// Width of the controls in the middle of a page.
    private static let controlWidth: CGFloat = 320

    // MARK: - Body

    internal var body: some View {
        switch step {
        case .welcome:
            welcomePage
        case .accessibility:
            accessibilityPage
        case .clipboard:
            clipboardPage
        case .model:
            modelPage
        case .finish:
            finishPage
        }
    }

    // MARK: - Pages

    private var welcomePage: some View {
        OnboardingPage(title: "欢迎使用 Gloss", message: "在任意 App 中选中文字即可离线翻译。") {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 112, height: 112)
        } content: {
            EmptyView()
        }
    }

    private var accessibilityPage: some View {
        OnboardingPage(
            title: "辅助功能权限",
            message: "需要“辅助功能”权限以读取其他 App 中选中的文字。"
        ) {
            StepSymbol(name: "hand.raised.fill", color: .blue)
        } content: {
            if viewModel.accessibility.isTrusted {
                DoneLabel("已开启")
            } else {
                VStack(spacing: 10) {
                    Button("打开系统设置") {
                        viewModel.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("系统设置 → 隐私与安全性 → 辅助功能")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var clipboardPage: some View {
        OnboardingPage(
            title: "剪贴板权限",
            message: "部分 App 无法直接读取选中的文字，需通过剪贴板临时复制并恢复原内容。"
        ) {
            StepSymbol(name: "doc.on.clipboard.fill", color: .orange)
        } content: {
            if viewModel.clipboard.isAllowed {
                DoneLabel("已允许")
            } else {
                VStack(spacing: 10) {
                    Button("打开系统设置") {
                        viewModel.requestClipboardAccess()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    Text("在“隐私与安全性”中设为“始终允许”")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var modelPage: some View {
        OnboardingPage(
            title: "下载翻译模型",
            message: "腾讯混元 Hy-MT2 本地翻译模型，约 \(ModelManifest.totalSize.formatted(.byteCount(style: .file)))。"
        ) {
            StepSymbol(name: "arrow.down", color: .purple)
        } content: {
            modelControls
        }
    }

    @ViewBuilder
    private var modelControls: some View {
        switch viewModel.model.state {
        case .notDownloaded:
            VStack(spacing: 12) {
                Button("下载") {
                    viewModel.downloadModel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                sourcePicker
            }
        case .downloading(let received, let total):
            VStack(spacing: 8) {
                ProgressView(value: ModelProgressFormat.fraction(received: received, total: total))
                HStack {
                    Text(ModelProgressFormat.bytes(received: received, total: total))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("取消") {
                        viewModel.cancelDownload()
                    }
                    .buttonStyle(.link)
                }
                .font(.callout)
                Text("下载将在后台继续")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
            .frame(width: Self.controlWidth)
        case .verifying:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("校验中…")
                    .foregroundStyle(.secondary)
            }
        case .downloadFailed(let failure):
            VStack(spacing: 12) {
                Label {
                    Text(failure.message)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
                Button("重试") {
                    viewModel.downloadModel()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                sourcePicker
            }
        case .loading, .ready:
            DoneLabel("已下载")
        case .loadFailed:
            VStack(spacing: 12) {
                Label("加载失败", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Button("重试") {
                    viewModel.retryModelLoad()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    private var sourcePicker: some View {
        @Bindable var store = viewModel.settingsStore
        return Picker("下载源", selection: $store.modelSource) {
            ForEach(ModelSource.allCases, id: \.self) { source in
                Text(source.title).tag(source)
            }
        }
        .pickerStyle(.menu)
        .fixedSize()
        .font(.callout)
    }

    private enum FinishState {
        case ready
        case downloading
        case incomplete

        var title: LocalizedStringKey {
            switch self {
            case .ready: "准备就绪"
            case .downloading: "模型下载中"
            case .incomplete: "设置未完成"
            }
        }

        var symbolName: String {
            switch self {
            case .ready: "checkmark"
            case .downloading: "arrow.down"
            case .incomplete: "exclamationmark"
            }
        }

        var symbolColor: Color {
            switch self {
            case .ready: .green
            case .downloading: .blue
            case .incomplete: .orange
            }
        }

        func message(menuBarIcon: Image) -> LocalizedStringKey {
            switch self {
            case .ready:
                "选中文字即可翻译，可在菜单栏 \(menuBarIcon) 中打开设置。"
            case .downloading:
                "下载完成后即可翻译，可在菜单栏 \(menuBarIcon) 中查看进度。"
            case .incomplete:
                "稍后可在菜单栏 \(menuBarIcon) 中完成设置。"
            }
        }
    }

    private var finishState: FinishState {
        guard viewModel.accessibility.isTrusted else { return .incomplete }
        switch viewModel.model.state {
        case .ready, .loading:
            return .ready
        case .downloading, .verifying:
            return .downloading
        case .notDownloaded, .downloadFailed, .loadFailed:
            return .incomplete
        }
    }

    private var finishPage: some View {
        let state = finishState
        return OnboardingPage(
            title: state.title,
            message: state.message(menuBarIcon: Image(nsImage: MenuBarIcon.image))
        ) {
            StepSymbol(name: state.symbolName, color: state.symbolColor)
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                ChecklistRow(title: "辅助功能", status: viewModel.accessibility.isTrusted ? .done("已开启") : .pending("未开启"))
                if viewModel.settingsStore.settings.usesCopyFallback {
                    ChecklistRow(
                        title: "剪贴板读取",
                        status: viewModel.clipboard.isAllowed ? .done("已允许") : .skipped("未允许")
                    )
                }
                ChecklistRow(title: "翻译模型", status: modelChecklistStatus)
            }
            .frame(width: 240)
        }
    }

    private var modelChecklistStatus: ChecklistRow.Status {
        switch viewModel.model.state {
        case .notDownloaded:
            .pending("未下载")
        case .downloading(let received, let total):
            .progress(ModelProgressFormat.fraction(received: received, total: total))
        case .verifying:
            .working("校验中…")
        case .downloadFailed:
            .pending("下载失败")
        case .loading:
            .working("加载中…")
        case .ready:
            .done("已就绪")
        case .loadFailed:
            .pending("加载失败")
        }
    }
}

// MARK: - OnboardingPage

/// A page of the guide: a picture, a title and an explanation, and the page's controls below.
private struct OnboardingPage<Icon: View, Content: View>: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    @ViewBuilder let icon: Icon
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            icon
                .padding(.bottom, 22)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .padding(.bottom, 10)
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 400)
                .padding(.bottom, 26)
            content
                .frame(minHeight: 96, alignment: .top)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - StepSymbol

/// A page's symbol on a colored tile, in the shape of an app icon.
private struct StepSymbol: View {
    let name: String
    let color: Color

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 34, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 76, height: 76)
            .background(color.gradient, in: .rect(cornerRadius: 18))
    }
}

// MARK: - DoneLabel

/// Shown in place of a page's controls once it's done.
private struct DoneLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        }
        .font(.headline)
    }
}

// MARK: - ChecklistRow

/// One item of the summary on the last page.
private struct ChecklistRow: View {
    enum Status {
        case done(LocalizedStringKey)
        case working(LocalizedStringKey)
        /// Under way with a known share done, from 0 to 1: a ring that fills up, and the percentage.
        case progress(Double)
        /// Optional and not done.
        case skipped(LocalizedStringKey)
        case pending(LocalizedStringKey)
    }

    let title: LocalizedStringKey
    let status: Status

    var body: some View {
        HStack(spacing: 8) {
            icon
                .frame(width: 18)
            Text(title)
            Spacer()
            statusText
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var icon: some View {
        switch status {
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .working:
            ProgressView()
                .controlSize(.mini)
        case .progress(let fraction):
            ProgressRing(fraction: fraction)
        case .skipped:
            Image(systemName: "minus.circle.fill")
                .foregroundStyle(.tertiary)
        case .pending:
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var statusText: Text {
        switch status {
        case .done(let text), .working(let text), .skipped(let text), .pending(let text):
            Text(text)
        case .progress(let fraction):
            // Steady digits, so the row doesn't jitter as the number climbs.
            Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                .monospacedDigit()
        }
    }
}
