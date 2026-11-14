//
//  GlossSettingsTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Testing
import HyMTKit
@testable import Gloss

@MainActor
struct GlossSettingsTests {
    // MARK: - Defaults

    @Test func testDefaultsTranslateEveryLanguageIntoChinese() {
        #expect(GlossSettings.default.targetLanguage == .chinese)
        #expect(GlossSettings.default.triggerLanguages == Set(HyMTLanguage.allCases))
    }

    @Test func testDefaultsAreEnabledWithTheCopyFallback() {
        #expect(GlossSettings.default.isEnabled)
        #expect(GlossSettings.default.usesCopyFallback)
    }

    @Test func testDefaultsExcludeDeveloperTools() {
        #expect(GlossSettings.default.isExcluded("com.apple.dt.Xcode"))
        #expect(GlossSettings.default.isExcluded("com.superlogical.rex"))
        #expect(!GlossSettings.default.isExcluded("com.apple.Safari"))
    }

    @Test func testDefaultTranslationFontSizeIsOffered() {
        #expect(GlossSettings.default.translationFontSize == 14)
        #expect(GlossSettings.translationFontSizes.contains(GlossSettings.default.translationFontSize))
    }

    // MARK: - Persistence

    @Test func testTranslationFontSizePersistsAcrossLaunches() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.settings.translationFontSize = 18

        #expect(SettingsStore(defaults: defaults).settings.translationFontSize == 18)
    }

    @Test func testFontSizeThatIsNotOfferedFallsBackToTheDefault() throws {
        let settings = try JSONDecoder().decode(GlossSettings.self, from: Data(#"{"translationFontSize":300}"#.utf8))
        #expect(settings.translationFontSize == GlossSettings.default.translationFontSize)
    }

    @Test func testLanguageChangesPersistAcrossLaunches() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.settings.targetLanguage = .japanese
        store.setTrigger(.french, enabled: false)
        let reloaded = SettingsStore(defaults: defaults).settings

        #expect(reloaded.targetLanguage == .japanese)
        #expect(reloaded.triggerLanguages == Set(HyMTLanguage.allCases).subtracting([.french]))
    }

    @Test func testExcludedAppChangesPersistAcrossLaunches() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.setExcluded(true, bundleID: "com.apple.Safari")
        store.setExcluded(false, bundleID: "com.apple.dt.Xcode")
        let reloaded = SettingsStore(defaults: defaults).settings

        #expect(reloaded.isExcluded("com.apple.Safari"))
        #expect(!reloaded.isExcluded("com.apple.dt.Xcode"))
    }

    @Test func testSelectingAllLanguagesTurnsEveryOneOn() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.setTriggers(LanguageDetector.triggerCandidates, enabled: false)
        store.setTrigger(.english, enabled: true)
        store.setTriggers(LanguageDetector.triggerCandidates, enabled: true)

        #expect(Set(LanguageDetector.triggerCandidates).isSubset(of: store.settings.triggerLanguages))
    }

    @Test func testClearingAllLanguagesTurnsEveryOneOff() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = SettingsStore(defaults: defaults)
        store.setTriggers(LanguageDetector.triggerCandidates, enabled: false)

        #expect(store.settings.triggerLanguages.isDisjoint(with: LanguageDetector.triggerCandidates))
    }

    @Test func testMissingKeysFallBackToDefaults() throws {
        let settings = try JSONDecoder().decode(GlossSettings.self, from: Data(#"{"targetLanguage":"de"}"#.utf8))
        #expect(settings.targetLanguage == .german)
        #expect(settings.triggerLanguages == GlossSettings.default.triggerLanguages)
        #expect(settings.excludedBundleIDs == GlossSettings.default.excludedBundleIDs)
        #expect(settings.translationFontSize == GlossSettings.default.translationFontSize)
    }

    @Test func testModelSourceIsNotPickedByDefault() {
        #expect(GlossSettings.default.modelSource == nil)
    }

    @Test func testUnknownModelSourceCountsAsNotPicked() throws {
        let json = #"{"modelSource":"somewhereElse","targetLanguage":"de"}"#
        let settings = try JSONDecoder().decode(GlossSettings.self, from: Data(json.utf8))
        #expect(settings.modelSource == nil)
        #expect(settings.targetLanguage == .german)
    }

    @Test func testUnreadableSettingsFallBackToDefaults() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not json".utf8), forKey: "settings")

        #expect(SettingsStore(defaults: defaults).settings == .default)
    }

    // MARK: - Private

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "GlossTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
