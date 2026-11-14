//
//  ExcludedAppsSettingsView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import SwiftUI
import UniformTypeIdentifiers

/// Settings ▸ Apps: the apps whose selections aren't translated.
internal struct ExcludedAppsSettingsView: View {
    // MARK: - Properties

    internal var settingsStore: SettingsStore

    // MARK: - Body

    internal var body: some View {
        Form {
            Section("不翻译的 App") {
                ForEach(excludedApps) { app in
                    row(app)
                }
                Button {
                    addApps()
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.borderless)
                .help("添加")
                .accessibilityLabel("添加")
            }
        }
        .formStyle(.grouped)
        // A long list scrolls rather than stretching the window down the screen.
        .frame(maxHeight: SettingsLayout.maximumListHeight)
    }

    // MARK: - Rows

    private func row(_ app: InstalledApp) -> some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 18, height: 18)
            Text(app.name)
            Spacer()
            Button {
                settingsStore.setExcluded(false, bundleID: app.bundleID)
            } label: {
                Image(systemName: "minus.circle.fill")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("移除")
            .accessibilityLabel("移除")
        }
    }

    // MARK: - Private

    /// Excluded apps that are installed; defaults for apps the user doesn't have stay hidden.
    private var excludedApps: [InstalledApp] {
        settingsStore.settings.excludedBundleIDs.compactMap(InstalledApp.init(bundleID:))
    }

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(filePath: "/Applications")
        panel.prompt = String(localized: "添加")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let bundleID = Bundle(url: url)?.bundleIdentifier else { continue }
            settingsStore.setExcluded(true, bundleID: bundleID)
        }
    }
}

// MARK: - InstalledApp

/// An installed app shown in the list.
private struct InstalledApp: Identifiable {
    let bundleID: String
    let name: String
    let icon: NSImage

    var id: String {
        bundleID
    }

    init?(bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        self.bundleID = bundleID
        name = FileManager.default.displayName(atPath: url.path)
        icon = NSWorkspace.shared.icon(forFile: url.path)
    }
}
