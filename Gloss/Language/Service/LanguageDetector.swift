//
//  LanguageDetector.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import NaturalLanguage
import HyMTKit

/// Detects which Hy-MT2 language a selection is written in.
internal enum LanguageDetector {
    // MARK: - Properties

    /// Hy-MT2 languages NaturalLanguage can recognize, keyed by their `NLLanguage`.
    internal static let detectableLanguages: [NLLanguage: HyMTLanguage] = Dictionary(
        uniqueKeysWithValues: HyMTLanguage.allCases.compactMap { language in
            nlLanguage(for: language).map { ($0, language) }
        }
    )

    /// Languages offered as "languages to translate", in Hy-MT2's order.
    internal static let triggerCandidates: [HyMTLanguage] = HyMTLanguage.allCases.filter { nlLanguage(for: $0) != nil }

    /// Text with at most this many words counts as short (single words, names).
    private static let shortTextWordLimit = 3
    private static let minimumLetterShare = 0.4

    // MARK: - Detection

    /// Detects the language of a selection.
    /// - Parameters:
    ///   - text: Trimmed selected text.
    ///   - preferred: Languages to lean toward for very short text (the languages to translate), so ambiguous words
    ///     such as "taxi" or "Paris" count as English.
    /// - Returns: The language, or `nil` when the text isn't prose (URLs, numbers, symbols) or detection is unsure.
    internal static func detect(_ text: String, preferring preferred: Set<HyMTLanguage>) -> HyMTLanguage? {
        guard looksLikeProse(text) else { return nil }
        let isShort = text.split(whereSeparator: \.isWhitespace).count <= shortTextWordLimit

        let recognizer = NLLanguageRecognizer()
        recognizer.languageConstraints = Array(detectableLanguages.keys)
        if isShort {
            let hints = preferred.compactMap(nlLanguage(for:)).map { ($0, 0.8) }
            recognizer.languageHints = Dictionary(uniqueKeysWithValues: hints)
        }
        recognizer.processString(text)

        let hypotheses = recognizer.languageHypotheses(withMaximum: 5)
        guard let best = hypotheses.max(by: { $0.value < $1.value }),
              best.value >= (isShort ? 0.3 : 0.5),
              let language = detectableLanguages[best.key]
        else { return nil }
        // Japanese prose has kana; text made only of kanji is almost always Chinese.
        if language == .japanese, !containsKana(text) {
            let chinese = hypotheses
                .filter { $0.key == .simplifiedChinese || $0.key == .traditionalChinese }
                .max { $0.value < $1.value }
            return chinese.flatMap { detectableLanguages[$0.key] } ?? .chinese
        }
        return language
    }

    /// Whether the text reads as natural language: enough letters, and not just a link or an email address.
    internal static func looksLikeProse(_ text: String) -> Bool {
        let scalars = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
        guard !scalars.isEmpty else { return false }
        let letters = scalars.filter { CharacterSet.letters.contains($0) }.count
        guard Double(letters) / Double(scalars.count) >= minimumLetterShare else { return false }
        return !isLink(text)
    }

    /// The `NLLanguage` counterpart of a Hy-MT2 language, or `nil` when NaturalLanguage can't recognize it
    /// (Filipino, Uyghur and Cantonese).
    internal static func nlLanguage(for language: HyMTLanguage) -> NLLanguage? {
        switch language {
        case .chinese: .simplifiedChinese
        case .traditionalChinese: .traditionalChinese
        case .english: .english
        case .french: .french
        case .portuguese: .portuguese
        case .spanish: .spanish
        case .japanese: .japanese
        case .turkish: .turkish
        case .russian: .russian
        case .arabic: .arabic
        case .korean: .korean
        case .thai: .thai
        case .italian: .italian
        case .german: .german
        case .vietnamese: .vietnamese
        case .malay: .malay
        case .indonesian: .indonesian
        case .hindi: .hindi
        case .polish: .polish
        case .czech: .czech
        case .dutch: .dutch
        case .khmer: .khmer
        case .burmese: .burmese
        case .persian: .persian
        case .gujarati: .gujarati
        case .urdu: .urdu
        case .telugu: .telugu
        case .marathi: .marathi
        case .hebrew: .hebrew
        case .bengali: .bengali
        case .tamil: .tamil
        case .ukrainian: .ukrainian
        case .tibetan: .tibetan
        case .kazakh: .kazakh
        case .mongolian: .mongolian
        case .filipino, .uyghur, .cantonese: nil
        }
    }

    // MARK: - Private

    /// Whether the text contains hiragana or katakana (including half-width katakana).
    private static func containsKana(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3040...0x30FF, 0x31F0...0x31FF, 0xFF66...0xFF9F: true
            default: false
            }
        }
    }

    /// Whether the whole text is one link (URLs and email addresses both count).
    private static func isLink(_ text: String) -> Bool {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            // Creating a link detector with a valid type doesn't fail; treat a failure as "not a link".
            return false
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, options: [], range: range) else { return false }
        return match.range == range
    }
}
