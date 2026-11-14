//
//  SettingsStore.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Observation
import os
import HyMTKit

/// Holds ``GlossSettings`` and persists every change to `UserDefaults`.
@MainActor
@Observable
internal final class SettingsStore {
    // MARK: - Properties

    /// Current settings; assigning saves them.
    internal var settings: GlossSettings {
        didSet { save() }
    }

    /// Whether the user went through the welcome guide to its end; until then it opens at every launch.
    internal var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Self.onboardingKey) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private static let key = "settings"
    private static let onboardingKey = "hasCompletedOnboarding"
    private static let logger = Logger.gloss("SettingsStore")

    // MARK: - Lifecycle

    /// - Parameter defaults: Where settings are stored; tests pass a dedicated suite.
    internal init(defaults: UserDefaults) {
        self.defaults = defaults
        hasCompletedOnboarding = defaults.bool(forKey: Self.onboardingKey)
        guard let data = defaults.data(forKey: Self.key) else {
            settings = .default
            return
        }
        do {
            settings = try JSONDecoder().decode(GlossSettings.self, from: data)
        } catch {
            Self.logger.error("Stored settings are unreadable, using defaults: \(error.localizedDescription, privacy: .public)")
            settings = .default
        }
    }

    // MARK: - Queries

    /// Where the model is downloaded from: the user's pick, or else the source for their region.
    internal var modelSource: ModelSource {
        get { settings.modelSource ?? ModelManifest.defaultSource(forRegion: Locale.current.region?.identifier) }
        set { settings.modelSource = newValue }
    }

    // MARK: - Actions

    /// Adds or removes `bundleID` from the excluded apps.
    internal func setExcluded(_ excluded: Bool, bundleID: String) {
        var excludedIDs = settings.excludedBundleIDs.filter { $0 != bundleID }
        if excluded {
            excludedIDs.append(bundleID)
        }
        settings.excludedBundleIDs = excludedIDs
    }

    /// Turns translation of selections detected as `language` on or off.
    internal func setTrigger(_ language: HyMTLanguage, enabled: Bool) {
        if enabled {
            settings.triggerLanguages.insert(language)
        } else {
            settings.triggerLanguages.remove(language)
        }
    }

    /// Turns translation of all `languages` on or off at once (the "All" item).
    internal func setTriggers(_ languages: [HyMTLanguage], enabled: Bool) {
        if enabled {
            settings.triggerLanguages.formUnion(languages)
        } else {
            settings.triggerLanguages.subtract(languages)
        }
    }

    // MARK: - Private

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(settings), forKey: Self.key)
        } catch {
            Self.logger.error("Failed to save settings: \(error.localizedDescription, privacy: .public)")
        }
    }
}
