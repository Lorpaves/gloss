//
//  PermissionSettingsView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import SwiftUI

/// Settings ▸ Permissions: what Gloss is allowed to do, with a way to allow what it isn't.
internal struct PermissionSettingsView: View {
    // MARK: - Properties

    internal var settingsStore: SettingsStore
    internal var accessibility: AccessibilityPermission
    internal var clipboard: ClipboardPermission

    // MARK: - Body

    internal var body: some View {
        @Bindable var store = settingsStore
        Form {
            Section {
                LabeledContent("辅助功能") {
                    status(isGranted: accessibility.isTrusted, grantedTitle: "已开启", requestTitle: "去开启") {
                        accessibility.requestAccess()
                    }
                }
                LabeledContent("剪贴板读取") {
                    status(isGranted: clipboard.isAllowed, grantedTitle: "已允许", requestTitle: "去允许") {
                        clipboard.request()
                    }
                }
            }
            Section {
                Toggle("无法直接取词时改用剪贴板", isOn: $store.settings.usesCopyFallback)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .task {
            clipboard.refresh()
        }
    }

    // MARK: - Private

    @ViewBuilder
    private func status(
        isGranted: Bool,
        grantedTitle: LocalizedStringKey,
        requestTitle: LocalizedStringKey,
        action: @escaping @MainActor () -> Void
    ) -> some View {
        if isGranted {
            Label(grantedTitle, systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        } else {
            Button(requestTitle, action: action)
        }
    }
}
