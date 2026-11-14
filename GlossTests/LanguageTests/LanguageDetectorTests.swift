//
//  LanguageDetectorTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Testing
import HyMTKit
@testable import Gloss

struct LanguageDetectorTests {
    @Test(arguments: [
        ("The quick brown fox jumps over the lazy dog.", HyMTLanguage.english),
        ("今天天气真好，我们一起去公园散步吧。", HyMTLanguage.chinese),
        ("今天天氣真好，我們一起去公園散步吧。", HyMTLanguage.traditionalChinese),
        ("今日はとても良い天気ですね。散歩に行きましょう。", HyMTLanguage.japanese),
        ("Bonjour, comment allez-vous aujourd'hui ?", HyMTLanguage.french),
        ("Guten Morgen, wie geht es Ihnen heute?", HyMTLanguage.german)
    ])
    func testSentenceIsDetectedInItsLanguage(text: String, expected: HyMTLanguage) {
        #expect(LanguageDetector.detect(text, preferring: [.english]) == expected)
    }

    @Test(arguments: ["hello", "beautiful", "machine learning"])
    func testShortEnglishLeansTowardTheLanguagesToTranslate(text: String) {
        #expect(LanguageDetector.detect(text, preferring: [.english]) == .english)
    }

    @Test(arguments: ["中文翻译", "今天天气真好", "機器翻譯"])
    func testKanjiOnlyTextCountsAsChinese(text: String) {
        let language = LanguageDetector.detect(text, preferring: Set(HyMTLanguage.allCases))
        #expect(language == .chinese || language == .traditionalChinese)
    }

    @Test(arguments: ["https://www.apple.com/macos/", "someone@example.com", "2026-11-13 18:00", "12345", "→ ← ↑ ↓", "   "])
    func testTextThatIsNotProseIsIgnored(text: String) {
        #expect(LanguageDetector.detect(text, preferring: [.english]) == nil)
    }

    @Test func testThirtyFiveLanguagesAreDetectable() {
        #expect(LanguageDetector.detectableLanguages.count == 35)
    }

    @Test func testDetectableLanguagesMapBothWays() {
        let mismatched = LanguageDetector.detectableLanguages.filter { LanguageDetector.nlLanguage(for: $0.value) != $0.key }
        #expect(mismatched.isEmpty)
    }

    /// NaturalLanguage may add a script (Mongolian is `mn-Mong`); the language part must match Hy-MT2's code.
    @Test func testLanguageCodesMatchNaturalLanguageIgnoringScript() {
        let mismatched = HyMTLanguage.allCases.filter { language in
            guard !language.isChineseVariety, let nlLanguage = LanguageDetector.nlLanguage(for: language) else {
                return false
            }
            return nlLanguage.rawValue.split(separator: "-").first.map(String.init) != language.rawValue
        }
        #expect(mismatched.isEmpty)
    }

    @Test(arguments: [HyMTLanguage.filipino, .uyghur, .cantonese])
    func testUndetectableLanguagesAreNotOfferedAsLanguagesToTranslate(language: HyMTLanguage) {
        #expect(LanguageDetector.nlLanguage(for: language) == nil)
        #expect(!LanguageDetector.triggerCandidates.contains(language))
    }
}
