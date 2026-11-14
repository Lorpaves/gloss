//
//  ModelSettingsView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import SwiftUI

/// Settings ▸ Model: the translation model, its download, and where it comes from.
internal struct ModelSettingsView: View {
    // MARK: - Properties

    internal var model: ModelManager
    internal var settingsStore: SettingsStore

    @State private var isConfirmingDeletion = false

    // MARK: - Body

    internal var body: some View {
        @Bindable var store = settingsStore
        Form {
            Section {
                LabeledContent("模型") {
                    Text(verbatim: "Hy-MT2 1.8B · Q4_K_M")
                }
                LabeledContent("大小") {
                    Text(ModelManifest.totalSize.formatted(.byteCount(style: .file)))
                }
                LabeledContent {
                    ModelStatusRow(model: model, source: store.modelSource)
                } label: {
                    Text("状态")
                    // A second line while downloading, so the row's right side holds just the bar and the button.
                    if case .downloading(let received, let total) = model.state {
                        Text(ModelProgressFormat.bytes(received: received, total: total))
                            .monospacedDigit()
                    }
                }
            }
            Section {
                Picker("下载源", selection: $store.modelSource) {
                    ForEach(ModelSource.allCases, id: \.self) { source in
                        Text(source.title).tag(source)
                    }
                }
                .disabled(isDownloading)
            }
            if model.isInstalled {
                Section {
                    HStack {
                        Button("在访达中显示") {
                            model.revealInFinder()
                        }
                        Spacer()
                        Button("删除模型…", role: .destructive) {
                            isConfirmingDeletion = true
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .confirmationDialog("删除翻译模型？", isPresented: $isConfirmingDeletion) {
            Button("删除", role: .destructive) {
                model.delete()
            }
        } message: {
            Text("删除后需要重新下载才能继续翻译。")
        }
    }

    // MARK: - Private

    private var isDownloading: Bool {
        switch model.state {
        case .downloading, .verifying:
            true
        case .notDownloaded, .downloadFailed, .loading, .ready, .loadFailed:
            false
        }
    }
}

// MARK: - ModelStatusRow

/// The model's state, with the action that moves it on.
private struct ModelStatusRow: View {
    var model: ModelManager
    var source: ModelSource

    var body: some View {
        switch model.state {
        case .notDownloaded:
            HStack(spacing: 8) {
                Text("未下载")
                    .foregroundStyle(.secondary)
                Button("下载") {
                    model.download(from: source)
                }
            }
        case .downloading(let received, let total):
            // The sizes are the row's subtitle.
            HStack(spacing: 8) {
                ProgressRing(
                    fraction: ModelProgressFormat.fraction(received: received, total: total),
                    diameter: 16,
                    lineWidth: 2.5
                )
                Button {
                    model.cancelDownload()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("取消")
                .accessibilityLabel("取消")
            }
        case .verifying:
            progress("校验中…")
        case .downloadFailed(let failure):
            HStack(spacing: 8) {
                Text(failure.message)
                    .foregroundStyle(.red)
                Button("重试") {
                    model.download(from: source)
                }
            }
        case .loading:
            progress("加载中…")
        case .ready:
            Label("已就绪", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        case .loadFailed:
            HStack(spacing: 8) {
                Text("加载失败")
                    .foregroundStyle(.red)
                Button("重试") {
                    model.retryLoad()
                }
            }
        }
    }

    private func progress(_ title: LocalizedStringKey) -> some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}
