//
//  TriggerRuleTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Testing
import HyMTKit
@testable import Gloss

struct TriggerRuleTests {
    private static let chineseSentence = "今天天气真好，我们一起去公园散步吧。"

    @Test func testLanguageToTranslateIsTranslated() {
        #expect(TriggerRule.evaluate("The weather is lovely today.", settings: .default) == .translate(.english))
    }

    @Test func testTargetLanguageIsIgnored() {
        #expect(TriggerRule.evaluate(Self.chineseSentence, settings: .default) == .ignore)
    }

    @Test func testEveryOtherLanguageIsTranslatedByDefault() {
        #expect(TriggerRule.evaluate("Bonjour, comment allez-vous aujourd'hui ?", settings: .default) == .translate(.french))
    }

    @Test func testDeselectedLanguageIsIgnored() {
        var settings = GlossSettings.default
        settings.triggerLanguages.remove(.french)
        #expect(TriggerRule.evaluate("Bonjour, comment allez-vous aujourd'hui ?", settings: settings) == .ignore)
    }

    @Test func testTargetLanguageIsNeverTranslatedIntoItself() {
        var settings = GlossSettings.default
        settings.triggerLanguages = [.english, .chinese]
        #expect(TriggerRule.evaluate(Self.chineseSentence, settings: settings) == .ignore)
    }

    @Test func testChosenLanguagesReplaceTheDefaults() {
        var settings = GlossSettings.default
        settings.targetLanguage = .english
        settings.triggerLanguages = [.chinese]
        #expect(TriggerRule.evaluate(Self.chineseSentence, settings: settings) == .translate(.chinese))
    }

    @Test(arguments: ["中文", "今天天气真好", "机器翻译"])
    func testSimplifiedChineseIsNeverTranslatedIntoSimplifiedChinese(text: String) {
        #expect(TriggerRule.evaluate(text, settings: .default) == .ignore)
    }

    @Test func testTraditionalChineseIsTranslatedIntoSimplifiedChinese() {
        #expect(TriggerRule.evaluate("今天天氣真好，我們一起去公園散步吧。", settings: .default) == .translate(.traditionalChinese))
    }

    @Test func testVeryLongSelectionIsTranslatedLikeAnyOther() {
        let long = String(repeating: "This sentence is part of a very long selection. ", count: 1000)
        #expect(TriggerRule.evaluate(long, settings: .default) == .translate(.english))
    }
}
