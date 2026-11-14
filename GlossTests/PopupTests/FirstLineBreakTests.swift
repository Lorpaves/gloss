//
//  FirstLineBreakTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import Testing
@testable import Gloss

struct FirstLineBreakTests {
    private let font = NSFont.systemFont(ofSize: 14)
    private let sentence = "Adding Equatable conformance to your custom types means that you can use more convenient APIs."

    @Test func testTextThatFitsStaysOnTheFirstLine() {
        let lines = FirstLineBreak.split("Hello", font: font, width: 300)
        #expect(lines.firstLine == "Hello")
        #expect(lines.rest.isEmpty)
    }

    @Test func testLongTextBreaksBetweenWords() {
        let lines = FirstLineBreak.split(sentence, font: font, width: 200)
        #expect(!lines.rest.isEmpty)
        #expect(lines.firstLine + " " + lines.rest == sentence)
    }

    @Test func testFirstLineFitsItsWidth() {
        let lines = FirstLineBreak.split(sentence, font: font, width: 200)
        #expect((lines.firstLine as NSString).size(withAttributes: [.font: font]).width <= 200)
    }

    @Test func testLineBreakEndsTheFirstLine() {
        let lines = FirstLineBreak.split("第一行\n第二行", font: font, width: 300)
        #expect(lines.firstLine == "第一行")
        #expect(lines.rest == "第二行")
    }

    @Test func testChineseBreaksBetweenCharacters() {
        let text = String(repeating: "翻译", count: 40)
        let lines = FirstLineBreak.split(text, font: font, width: 200)
        #expect(!lines.firstLine.isEmpty)
        #expect(lines.firstLine + lines.rest == text)
    }

    @Test func testWidthNarrowerThanACharacterStillTakesOne() {
        let lines = FirstLineBreak.split("翻译", font: font, width: 1)
        #expect(lines.firstLine == "翻")
        #expect(lines.rest == "译")
    }

    @Test func testEmptyTextHasNoRest() {
        let lines = FirstLineBreak.split("", font: font, width: 200)
        #expect(lines.firstLine.isEmpty)
        #expect(lines.rest.isEmpty)
    }

    /// Text much longer than a line is only looked at up to a limit; that limit must not fall inside an emoji.
    @Test func testVeryLongTextIsSplitWithoutLosingCharacters() {
        let text = "a" + String(repeating: "😀", count: 400)
        let lines = FirstLineBreak.split(text, font: font, width: 200)
        #expect(lines.firstLine + lines.rest == text)
    }
}
