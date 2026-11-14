//
//  GlossSettings.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import HyMTKit

/// User preferences for selection translation.
internal struct GlossSettings: Equatable, Sendable {
    // MARK: - Properties

    /// Master switch for translating selections.
    internal var isEnabled: Bool
    /// Language translations are written in.
    internal var targetLanguage: HyMTLanguage
    /// Selections detected in one of these languages are translated; the target language never is.
    internal var triggerLanguages: Set<HyMTLanguage>
    /// Copies the selection through the app's Copy menu item when Accessibility can't read it.
    internal var usesCopyFallback: Bool
    /// Bundle identifiers of apps whose selections are ignored.
    internal var excludedBundleIDs: [String]
    /// Point size of the translation in the popup; one of ``translationFontSizes``.
    internal var translationFontSize: Double
    /// Where the translation model is downloaded from; `nil` until the user picks one (see
    /// ``SettingsStore/modelSource``).
    internal var modelSource: ModelSource?

    /// Sizes the translation can be shown at.
    internal static let translationFontSizes: [Double] = [12, 13, 14, 15, 16, 18, 20, 24]

    /// Defaults: translate every language into Chinese everywhere except developer tools.
    internal static let `default` = GlossSettings(
        isEnabled: true,
        targetLanguage: .chinese,
        triggerLanguages: Set(HyMTLanguage.allCases),
        usesCopyFallback: true,
        excludedBundleIDs: [
            "com.apple.dt.Xcode",
            "com.apple.Terminal",
            "com.googlecode.iterm2",
            "com.microsoft.VSCode",
            "com.superlogical.rex",
            "com.mitchellh.ghostty"
        ],
        translationFontSize: 14,
        modelSource: nil
    )

    // MARK: - Lifecycle

    internal init(
        isEnabled: Bool,
        targetLanguage: HyMTLanguage,
        triggerLanguages: Set<HyMTLanguage>,
        usesCopyFallback: Bool,
        excludedBundleIDs: [String],
        translationFontSize: Double,
        modelSource: ModelSource?
    ) {
        self.isEnabled = isEnabled
        self.targetLanguage = targetLanguage
        self.triggerLanguages = triggerLanguages
        self.usesCopyFallback = usesCopyFallback
        self.excludedBundleIDs = excludedBundleIDs
        self.translationFontSize = translationFontSize
        self.modelSource = modelSource
    }

    // MARK: - Queries

    /// Whether selections in the app with `bundleID` are ignored.
    internal func isExcluded(_ bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return excludedBundleIDs.contains(bundleID)
    }
}

// MARK: - Codable

extension GlossSettings: Codable {
    private enum CodingKeys: String, CodingKey {
        case isEnabled
        case targetLanguage
        case triggerLanguages
        case usesCopyFallback
        case excludedBundleIDs
        case translationFontSize
        case modelSource
    }

    /// Missing keys (e.g. from an older version) fall back to the defaults instead of discarding everything.
    internal init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = GlossSettings.default
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? fallback.isEnabled
        targetLanguage = try container.decodeIfPresent(HyMTLanguage.self, forKey: .targetLanguage)
            ?? fallback.targetLanguage
        triggerLanguages = try container.decodeIfPresent(Set<HyMTLanguage>.self, forKey: .triggerLanguages)
            ?? fallback.triggerLanguages
        usesCopyFallback = try container.decodeIfPresent(Bool.self, forKey: .usesCopyFallback)
            ?? fallback.usesCopyFallback
        excludedBundleIDs = try container.decodeIfPresent([String].self, forKey: .excludedBundleIDs)
            ?? fallback.excludedBundleIDs
        // A size the popup doesn't offer (a hand-edited or damaged value) falls back as well.
        translationFontSize = try container.decodeIfPresent(Double.self, forKey: .translationFontSize)
            .flatMap { GlossSettings.translationFontSizes.contains($0) ? $0 : nil }
            ?? fallback.translationFontSize
        // An unknown source (from a newer version) means "not picked yet" rather than unreadable settings.
        modelSource = (try? container.decodeIfPresent(ModelSource.self, forKey: .modelSource)) ?? fallback.modelSource
    }

    internal func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(targetLanguage, forKey: .targetLanguage)
        try container.encode(triggerLanguages.map(\.rawValue).sorted(), forKey: .triggerLanguages)
        try container.encode(usesCopyFallback, forKey: .usesCopyFallback)
        try container.encode(excludedBundleIDs, forKey: .excludedBundleIDs)
        try container.encode(translationFontSize, forKey: .translationFontSize)
        try container.encodeIfPresent(modelSource, forKey: .modelSource)
    }
}
