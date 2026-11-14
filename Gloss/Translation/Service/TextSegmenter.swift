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
    /// Shortest line, in UTF-16 units, taken to fill a column of wrapped text, for alphabetic scripts.
    internal static let alphabeticWrapLength = 45
    /// Shortest line taken to fill a column of wrapped text, for other scripts.
    internal static let denseWrapLength = 20

    // MARK: - Splitting

    /// Splits text into segments: paragraphs first (see ``paragraphs(of:)``), then whole sentences packed up to
    /// the script's budget. Sentences longer than the budget are cut at whitespace.
    internal static func segments(of text: String) -> [Segment] {
        let budget = budget(for: text)
        var result: [Segment] = []
        for paragraph in paragraphs(of: text) {
            for (index, piece) in pack(sentences(of: paragraph.text), budget: budget).enumerated() {
                result.append(Segment(text: piece, lineBreaksBefore: index == 0 ? paragraph.lineBreaksBefore : 0))
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

    /// The paragraphs of a text, with the lines of a wrapped paragraph put back together.
    ///
    /// A selection in a PDF comes with a line break at the end of every row of a paragraph, and sometimes in the
    /// middle of a row. Translating those lines one by one would cut sentences apart, so within a block of lines
    /// that is wrapped prose (see ``isWrappedProse(_:)``) a line that stops mid-sentence is joined with the next
    /// one. Blank lines and lines that end their sentence still separate paragraphs, and blocks of short lines
    /// (list items, verse, labels) are left as they are.
    private static func paragraphs(of text: String) -> [Segment] {
        let lines = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        let first = lines.firstIndex { !$0.isEmpty }
        var result: [Segment] = []
        var blankLines = 0
        var continuesParagraph = false
        var isProse = false
        for (index, line) in lines.enumerated() {
            guard !line.isEmpty else {
                blankLines += 1
                continuesParagraph = false
                continue
            }
            if index == 0 || lines[index - 1].isEmpty {
                isProse = isWrappedProse(lines[index...].prefix { !$0.isEmpty })
            }
            if continuesParagraph, let paragraph = result.popLast() {
                let joined = paragraph.text + glue(between: paragraph.text, and: line) + line
                result.append(Segment(text: joined, lineBreaksBefore: paragraph.lineBreaksBefore))
            } else {
                result.append(Segment(text: line, lineBreaksBefore: result.isEmpty ? 0 : blankLines + 1))
            }
            blankLines = 0
            let next = index + 1 < lines.count ? lines[index + 1] : ""
            continuesParagraph = continues(line, onto: next, inProse: isProse, isFirst: index == first)
        }
        return result
    }

    /// Whether a block of consecutive lines is prose wrapped to fit a column: one of its lines, other than the
    /// last, fills a column and stops mid-sentence.
    private static func isWrappedProse(_ block: some Collection<String>) -> Bool {
        block.dropLast().contains { fillsColumn($0) && !endsSentence($0) }
    }

    /// Whether the sentence `line` stops in goes on in `next`.
    ///
    /// In wrapped prose it does, except that a short line before a capitalized one is taken for a heading or a
    /// list item. Elsewhere lines are kept apart unless the next one visibly continues the sentence: it starts
    /// in lower case, or the selection's first line (which may be the end of a row) is followed by a line that
    /// finishes the sentence. Lists with long items that have no closing punctuation look like wrapped prose and
    /// are joined too.
    private static func continues(_ line: String, onto next: String, inProse: Bool, isFirst: Bool) -> Bool {
        guard let start = next.first, !endsSentence(line), !startsListItem(next) else { return false }
        if inProse {
            return fillsColumn(line) || !start.isUppercase
        }
        return start.isLowercase || (isFirst && endsSentence(next))
    }

    /// Whether a line is long enough to have been wrapped to fit a column.
    private static func fillsColumn(_ line: String) -> Bool {
        line.utf16.count >= (budget(for: line) == alphabeticBudget ? alphabeticWrapLength : denseWrapLength)
    }

    /// Whether a line ends with sentence-final punctuation (or a colon or semicolon), closing quotes and
    /// brackets aside.
    private static func endsSentence(_ line: String) -> Bool {
        let closers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}", "」", "』", "】", "》", "〉", "）", "］", "｝", "»", "›"]
        let terminators: Set<Character> = [".", "!", "?", "…", ":", ";", "。", "！", "？", "．", "｡", "：", "；", "‼", "⁇", "⁈", "⁉"]
        guard let last = line.last(where: { !closers.contains($0) && !$0.isWhitespace }) else { return false }
        return terminators.contains(last)
    }

    /// Whether a line begins with a bullet or a number, as a list item does.
    private static func startsListItem(_ line: String) -> Bool {
        let bullets: Set<Character> = ["•", "·", "‣", "◦", "▪", "■", "●", "○", "–", "—", "-", "*", "+"]
        guard let first = line.first else { return false }
        if bullets.contains(first) {
            return line.dropFirst().first?.isWhitespace ?? true
        }
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= 3, let mark = line.dropFirst(digits.count).first else { return false }
        return mark == "." || mark == ")" || mark == "、" || mark == "．"
    }

    /// What joins two wrapped lines: nothing between characters of scripts written without spaces and after a
    /// word broken at a hyphen, otherwise a space.
    private static func glue(between line: String, and next: String) -> String {
        guard let last = line.last, let first = next.first else { return "" }
        if last == "-" || last == "‐", first.isLetter, line.dropLast().last?.isLetter == true {
            return ""
        }
        return isWrittenWithoutSpaces(last) && isWrittenWithoutSpaces(first) ? "" : " "
    }

    /// Whether a character belongs to a script that puts no spaces between words (Chinese, Japanese, Thai, Lao,
    /// Khmer, Burmese), or is punctuation of such a script.
    private static func isWrittenWithoutSpaces(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first else { return false }
        switch scalar.value {
        case 0x0E00...0x0EFF, 0x1000...0x109F, 0x1780...0x17FF, 0x2E80...0x30FF, 0x31F0...0x31FF, 0x3400...0x4DBF,
             0x4E00...0x9FFF, 0xF900...0xFAFF, 0xFF00...0xFF60, 0x20000...0x323AF:
            return true
        default:
            return false
        }
    }

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
