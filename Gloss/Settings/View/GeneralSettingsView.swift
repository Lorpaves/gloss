//
//  GeneralSettingsView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import SwiftUI
import HyMTKit

/// Settings ▸ General: what gets translated, and how the translation is shown. Labels and controls only.
internal struct GeneralSettingsView: View {
    // MARK: - Properties

    internal var settingsStore: SettingsStore
    internal var loginItem: LoginItem
    internal var updater: AppUpdater

    // MARK: - Body

    internal var body: some View {
        @Bindable var store = settingsStore
        @Bindable var updater = updater
        Form {
            Section {
                Toggle("划词翻译", isOn: $store.settings.isEnabled)
                Picker("目标语言", selection: $store.settings.targetLanguage) {
                    ForEach(HyMTLanguage.allCases, id: \.self) { language in
                        Text(language.displayName).tag(language)
                    }
                }
                LabeledContent("需要翻译的语言") {
                    Menu(triggerSummary) {
                        Toggle("全部", isOn: allTriggersBinding)
                        Divider()
                        ForEach(triggerChoices, id: \.self) { language in
                            Toggle(language.displayName, isOn: triggerBinding(for: language))
                        }
                    }
                    .fixedSize()
                }
                Picker("译文字号", selection: $store.settings.translationFontSize) {
                    ForEach(GlossSettings.translationFontSizes, id: \.self) { size in
                        Text(size.formatted()).tag(size)
                    }
                }
            }
            Section {
                Toggle("登录时打开", isOn: opensAtLoginBinding)
            }
            Section {
                Toggle("自动检查更新", isOn: $updater.automaticallyChecksForUpdates)
                LabeledContent("版本") {
                    HStack(spacing: 8) {
                        Text(updater.currentVersion)
                            .foregroundStyle(.secondary)
                        Button("检查更新…") {
                            updater.checkForUpdates()
                        }
                        .disabled(!updater.canCheckForUpdates)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .task {
            // It can be changed in System Settings ▸ General ▸ Login Items too.
            loginItem.refresh()
        }
    }

    // MARK: - Private

    /// Detectable languages other than the one translations are written in.
    private var triggerChoices: [HyMTLanguage] {
        LanguageDetector.triggerCandidates.filter { $0 != settingsStore.settings.targetLanguage }
    }

    /// "All", a count, or the few selected languages listed the way the system joins lists ("英语和日语").
    private var triggerSummary: String {
        let selected = triggerChoices.filter { settingsStore.settings.triggerLanguages.contains($0) }
        if selected.count == triggerChoices.count {
            return String(localized: "全部")
        }
        if selected.count > 3 {
            return String(localized: "\(selected.count) 种语言")
        }
        let summary = ListFormatter.localizedString(byJoining: selected.map(\.displayName))
        return summary.isEmpty ? "—" : summary
    }

    /// On when every language is selected; turning it on selects them all, turning it off clears them all.
    private var allTriggersBinding: Binding<Bool> {
        Binding(
            get: { triggerChoices.allSatisfy { settingsStore.settings.triggerLanguages.contains($0) } },
            set: { settingsStore.setTriggers(triggerChoices, enabled: $0) }
        )
    }

    private var opensAtLoginBinding: Binding<Bool> {
        Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        )
    }

    private func triggerBinding(for language: HyMTLanguage) -> Binding<Bool> {
        Binding(
            get: { settingsStore.settings.triggerLanguages.contains(language) },
            set: { settingsStore.setTrigger(language, enabled: $0) }
        )
    }
}

// MARK: - HyMTLanguage

private extension HyMTLanguage {
    /// Localized name in the app's active language.
    var displayName: String {
        let localization = Bundle.main.preferredLocalizations.first ?? "zh-Hans"
        if localization == "zh-Hans" || localization == "zh" {
            return chineseName
        }
        if localization.hasPrefix("en") {
            return englishName
        }
        let locale = Locale(identifier: localization)
        if let localized = locale.localizedString(forIdentifier: rawValue), !localized.isEmpty {
            return localized.prefix(1).uppercased(with: locale) + localized.dropFirst()
        }
        return localization.hasPrefix("zh") ? chineseName : englishName
    }
}
