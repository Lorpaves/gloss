//
//  MenuBarContentView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import SwiftUI

/// The menu bar menu. Status items only appear while something needs attention.
internal struct MenuBarContentView: View {
    // MARK: - Properties

    internal var coordinator: AppCoordinator

    // MARK: - Body

    internal var body: some View {
        if hasStatus {
            statusItems
            Divider()
        }
        Toggle("划词翻译", isOn: isEnabled)
        if let app = coordinator.lastExternalApp {
            if coordinator.isExcluded(app) {
                Button("在“\(app.name)”中启用") {
                    coordinator.toggleExclusion(of: app)
                }
            } else {
                Button("在“\(app.name)”中停用") {
                    coordinator.toggleExclusion(of: app)
                }
            }
        }
        Divider()
        Button("检查更新…") {
            coordinator.updater.checkForUpdates()
        }
        .disabled(!coordinator.updater.canCheckForUpdates)
        Button("设置…") {
            coordinator.showSettings()
        }
        .keyboardShortcut(",")
        Button("退出") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // MARK: - Private

    private var hasStatus: Bool {
        coordinator.model.state != .ready || !coordinator.accessibility.isTrusted || coordinator.needsClipboardAccess
            || coordinator.updater.availableVersion != nil
    }

    @ViewBuilder
    private var statusItems: some View {
        // A scheduled check found an update; it waits here rather than opening over the user's work.
        if let version = coordinator.updater.availableVersion {
            Button("有新版本 \(version)，点此更新…") {
                coordinator.updater.checkForUpdates()
            }
        }
        switch coordinator.model.state {
        case .notDownloaded:
            Button("下载翻译模型…") {
                coordinator.showSettings(tab: .model)
            }
        case .downloading(let received, let total):
            Text("正在下载模型（\(percent(received: received, total: total))）")
        case .verifying:
            Text("正在校验模型…")
        case .downloadFailed:
            Button("模型下载失败，点击重试") {
                coordinator.downloadModel()
            }
        case .loading:
            Text("正在加载模型…")
        case .loadFailed:
            Button("模型加载失败，点击重试") {
                coordinator.retryModelLoad()
            }
        case .ready:
            EmptyView()
        }
        if !coordinator.accessibility.isTrusted {
            Button("开启辅助功能权限…") {
                coordinator.openAccessibilitySettings()
            }
        }
        if coordinator.needsClipboardAccess {
            Button("允许读取剪贴板…") {
                coordinator.requestClipboardAccess()
            }
        }
    }

    private func percent(received: Int64, total: Int64) -> String {
        ModelProgressFormat.fraction(received: received, total: total).formatted(.percent.precision(.fractionLength(0)))
    }

    private var isEnabled: Binding<Bool> {
        Binding(
            get: { coordinator.settingsStore.settings.isEnabled },
            set: { coordinator.settingsStore.settings.isEnabled = $0 }
        )
    }
}
