//
//  TextSegmenter.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import NaturalLanguage
import HyMTKit

/// Splits long selections into pieces that fit Hy-MT2's 1024-token context, and joins their translations.
///
/// HyMTKit stops generating once prompt and output fill the context, which would silently cut off the
/// translation of a long selection; translating segment by segment avoids that.
internal enum TextSegmenter {
    /// A piece of the selection translated on its own.
    internal struct Segment: Equatable, Sendable {
        internal var text: String
        /// Line breaks between the previous segment and this one; 0 when it continues the same paragraph.
        internal var lineBreaksBefore: Int
    }

    // MARK: - Properties

    /// UTF-16 units per segment for alphabetic scripts (Latin, Greek, Cyrillic): roughly 250 prompt tokens.
    internal static let alphabeticBudget = 1000
    /// UTF-16 units per segment for other scripts (CJK, Thai, Arabic…), which take more tokens per character.
    internal static let denseBudget = 350

    // MARK: - Splitting

    /// Splits text into segments: paragraphs first, then whole sentences packed up to the script's budget.
    /// Sentences longer than the budget are cut at whitespace.
    internal static func segments(of text: String) -> [Segment] {
        let budget = budget(for: text)
        var result: [Segment] = []
        var blankLines = 0
        for line in text.components(separatedBy: .newlines) {
            let paragraph = line.trimmingCharacters(in: .whitespaces)
            guard !paragraph.isEmpty else {
                blankLines += 1
                continue
            }
            let breaks = result.isEmpty ? 0 : blankLines + 1
            blankLines = 0
            for (index, piece) in pack(sentences(of: paragraph), budget: budget).enumerated() {
                result.append(Segment(text: piece, lineBreaksBefore: index == 0 ? breaks : 0))
            }
        }
        return result
    }

    /// Splits a piece in two near its middle, at a sentence boundary or whitespace when possible.
    /// - Returns: Both halves, or `nil` when the text can't be split.
    internal static func halves(of text: String) -> (String, String)? {
        let parts = sentences(of: text)
        let first: String
        let second: String
        if parts.count >= 2 {
            let middle = parts.count / 2
            first = parts[..<middle].joined()
            second = parts[middle...].joined()
        } else {
            guard text.count >= 2 else { return nil }
            var middle = text.index(text.startIndex, offsetBy: text.count / 2)
            if let space = text[..<middle].lastIndex(where: \.isWhitespace), space > text.startIndex {
                middle = space
            }
            first = String(text[..<middle])
            second = String(text[middle...])
        }
        let trimmedFirst = first.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSecond = second.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedFirst.isEmpty, !trimmedSecond.isEmpty else { return nil }
        return (trimmedFirst, trimmedSecond)
    }

    /// Segment budget for a text: the alphabetic budget when most of its letters are Latin, Greek or Cyrillic.
    internal static func budget(for text: String) -> Int {
        var letters = 0
        var alphabetic = 0
        for scalar in text.unicodeScalars where CharacterSet.letters.contains(scalar) {
            letters += 1
            switch scalar.value {
            case 0x0041...0x024F, 0x1E00...0x1EFF, 0x0370...0x03FF, 0x0400...0x052F:
                alphabetic += 1
            default:
                break
            }
        }
        guard letters > 0 else { return alphabeticBudget }
        return Double(alphabetic) / Double(letters) >= 0.5 ? alphabeticBudget : denseBudget
    }

    // MARK: - Joining

    /// Joins segment translations in order. `translations` may be shorter than `segments` while streaming.
    internal static func join(_ translations: [String], segments: [Segment], target: HyMTLanguage) -> String {
        var result = ""
        for (index, translation) in translations.enumerated() {
            if index > 0 {
                let breaks = index < segments.count ? segments[index].lineBreaksBefore : 0
                result += breaks > 0 ? String(repeating: "\n", count: min(breaks, 2)) : separator(for: target)
            }
            result += translation.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    /// What goes between two sentences in the target language.
    internal static func separator(for target: HyMTLanguage) -> String {
        switch target {
        case .chinese, .traditionalChinese, .cantonese, .japanese:
            ""
        default:
            " "
        }
    }

    // MARK: - Private

    /// Sentences of a paragraph, keeping every character (including the spaces between sentences).
    private static func sentences(of paragraph: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = paragraph
        var starts: [String.Index] = []
        tokenizer.enumerateTokens(in: paragraph.startIndex..<paragraph.endIndex) { range, _ in
            starts.append(range.lowerBound)
            return true
        }
        guard !starts.isEmpty else { return [paragraph] }
        starts[0] = paragraph.startIndex
        return starts.indices.map { index in
            let end = index + 1 < starts.count ? starts[index + 1] : paragraph.endIndex
            return String(paragraph[starts[index]..<end])
        }
    }

    /// Greedily packs consecutive sentences into pieces of at most `budget` UTF-16 units.
    private static func pack(_ sentences: [String], budget: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for sentence in sentences.flatMap({ split($0, budget: budget) }) {
            if !current.isEmpty, current.utf16.count + sentence.utf16.count > budget {
                pieces.append(current)
                current = ""
            }
            current += sentence
        }
        pieces.append(current)
        return pieces
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// Cuts a sentence longer than the budget, preferring whitespace (scripts without spaces are cut anywhere).
    private static func split(_ sentence: String, budget: Int) -> [String] {
        guard sentence.utf16.count > budget else { return [sentence] }
        var pieces: [String] = []
        var remaining = Substring(sentence)
        while remaining.utf16.count > budget {
            var end = remaining.startIndex
            var units = 0
            for index in remaining.indices {
                let width = remaining[index].utf16.count
                guard units + width <= budget else { break }
                units += width
                end = remaining.index(after: index)
            }
            if let space = remaining[..<end].lastIndex(where: \.isWhitespace), space > remaining.startIndex {
                end = remaining.index(after: space)
            }
            if end == remaining.startIndex {
                // A single character wider than the budget; take it anyway.
                end = remaining.index(after: end)
            }
            pieces.append(String(remaining[..<end]))
            remaining = remaining[end...]
        }
        if !remaining.isEmpty {
            pieces.append(String(remaining))
        }
        return pieces
    }
}
