//
//  TextSegmenterTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Testing
import HyMTKit
@testable import Gloss

struct TextSegmenterTests {
    private static let longParagraph = String(
        repeating: "This is a sentence that is about seventy characters long, more or less. ",
        count: 40
    )
    private static let longChinese = String(repeating: "这是一个用来测试分段的中文句子。", count: 60)

    // MARK: - Splitting

    @Test func testShortTextStaysOneSegment() {
        let segments = TextSegmenter.segments(of: "Hello world. How are you?")
        #expect(segments == [TextSegmenter.Segment(text: "Hello world. How are you?", lineBreaksBefore: 0)])
    }

    @Test func testParagraphsBecomeSeparateSegments() {
        let segments = TextSegmenter.segments(of: "First paragraph.\n\nSecond paragraph.\nThird line.")
        #expect(segments.map(\.text) == ["First paragraph.", "Second paragraph.", "Third line."])
        #expect(segments.map(\.lineBreaksBefore) == [0, 2, 1])
    }

    @Test func testLongParagraphSplitsWithinTheBudget() {
        let segments = TextSegmenter.segments(of: Self.longParagraph)
        #expect(segments.count >= 3)
        #expect(segments.allSatisfy { $0.text.utf16.count <= TextSegmenter.alphabeticBudget })
    }

    @Test func testLongParagraphSplitsAtSentenceEnds() {
        let segments = TextSegmenter.segments(of: Self.longParagraph)
        #expect(segments.allSatisfy { $0.text.hasSuffix(".") })
        #expect(segments.dropFirst().allSatisfy { $0.lineBreaksBefore == 0 })
    }

    @Test func testSplittingLosesNoText() {
        let segments = TextSegmenter.segments(of: Self.longParagraph)
        #expect(segments.map(\.text).joined(separator: " ") == Self.longParagraph.trimmingCharacters(in: .whitespaces))
    }

    @Test func testChineseTextUsesTheSmallerBudget() {
        #expect(TextSegmenter.budget(for: Self.longChinese) == TextSegmenter.denseBudget)
    }

    @Test func testChineseSegmentsStayWithinTheBudgetAndLoseNothing() {
        let segments = TextSegmenter.segments(of: Self.longChinese)
        #expect(segments.allSatisfy { $0.text.utf16.count <= TextSegmenter.denseBudget })
        #expect(segments.map(\.text).joined() == Self.longChinese)
    }

    @Test func testOverlongSentenceIsCutBetweenWords() {
        let text = Array(repeating: "word", count: 400).joined(separator: " ")
        let segments = TextSegmenter.segments(of: text)
        #expect(segments.count == 2)
        #expect(segments.allSatisfy { $0.text.utf16.count <= TextSegmenter.alphabeticBudget })
        #expect(segments.allSatisfy { $0.text.split(separator: " ").allSatisfy { $0 == "word" } })
    }

    @Test func testHalvesSplitAtSentenceBoundaries() throws {
        let halves = try #require(TextSegmenter.halves(of: "One. Two. Three. Four."))
        #expect(halves.0 == "One. Two.")
        #expect(halves.1 == "Three. Four.")
    }

    @Test func testSingleCharacterCannotBeHalved() {
        #expect(TextSegmenter.halves(of: "x") == nil)
    }

    // MARK: - Joining

    @Test func testJoiningFollowsTheTargetLanguagesSpacing() {
        let segments = [
            TextSegmenter.Segment(text: "a", lineBreaksBefore: 0),
            TextSegmenter.Segment(text: "b", lineBreaksBefore: 0),
            TextSegmenter.Segment(text: "c", lineBreaksBefore: 2)
        ]
        #expect(TextSegmenter.join(["你好。", "再见。", "第二段。"], segments: segments, target: .chinese) == "你好。再见。\n\n第二段。")
        #expect(TextSegmenter.join(["Hello.", "Bye.", "Next."], segments: segments, target: .english) == "Hello. Bye.\n\nNext.")
    }

    @Test func testJoiningPartialTranslationsWhileStreaming() {
        let segments = [
            TextSegmenter.Segment(text: "a", lineBreaksBefore: 0),
            TextSegmenter.Segment(text: "b", lineBreaksBefore: 1)
        ]
        #expect(TextSegmenter.join(["Hello."], segments: segments, target: .english) == "Hello.")
        #expect(TextSegmenter.join(["Hello.", "Wor"], segments: segments, target: .english) == "Hello.\nWor")
    }
}
