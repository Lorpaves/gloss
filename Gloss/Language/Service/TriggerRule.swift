//
//  TriggerRule.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import HyMTKit

/// Decides whether a selection gets a translation popup.
internal enum TriggerRule {
    /// What to do with a selection.
    internal enum Decision: Equatable, Sendable {
        /// Translate from the detected language.
        case translate(HyMTLanguage)
        /// The selection is in a language to translate but too long to translate on selection.
        case tooLong
        /// Not a language to translate (or not prose at all).
        case ignore
    }

    /// Longer selections only get a "text too long" popup.
    internal static let maximumLength = 4000
    /// Detection only needs the beginning of long selections.
    private static let detectionPrefixLength = 1000

    /// - Parameters:
    ///   - text: Trimmed selected text.
    ///   - settings: The user's settings.
    /// - Returns: Translate when the text is detected as one of the languages to translate and differs from the
    ///   target language.
    internal static func evaluate(_ text: String, settings: GlossSettings) -> Decision {
        let sample = String(text.prefix(detectionPrefixLength))
        guard let language = LanguageDetector.detect(sample, preferring: settings.triggerLanguages),
              settings.triggerLanguages.contains(language),
              language != settings.targetLanguage,
              !isWrittenInTargetScript(sample, detected: language, target: settings.targetLanguage)
        else { return .ignore }
        return text.count > maximumLength ? .tooLong : .translate(language)
    }

    /// Whether Chinese text detected as the other script has no characters specific to it, e.g. "中文" taken for
    /// Traditional Chinese while translating into Simplified Chinese. Such text is the target language itself.
    private static func isWrittenInTargetScript(_ text: String, detected: HyMTLanguage, target: HyMTLanguage) -> Bool {
        let transform: StringTransform
        switch (detected, target) {
        case (.traditionalChinese, .chinese):
            transform = StringTransform("Hant-Hans")
        case (.chinese, .traditionalChinese):
            transform = StringTransform("Hans-Hant")
        default:
            return false
        }
        return text.applyingTransform(transform, reverse: false) == text
    }
}
