//
//  HyMTPromptBuilderTests.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation
import Testing
@testable import HyMTKit

struct HyMTPromptBuilderTests {
    @Test func chineseTargetUsesChineseTemplateWithChineseName() {
        let prompt = HyMTPromptBuilder.prompt(for: "Good morning", source: .english, target: .chinese)
        #expect(prompt == "将以下文本翻译为中文，注意只需要输出翻译后的结果，不要额外解释：\n\nGood morning")
    }

    @Test func nonChinesePairUsesEnglishTemplateWithEnglishName() {
        let prompt = HyMTPromptBuilder.prompt(for: "Hello", source: .english, target: .french)
        #expect(prompt.hasPrefix("Translate the following text into French. Note that you should only output"))
        #expect(prompt.hasSuffix(":\n\nHello"))
    }

    @Test func chineseSourceIsDetectedWhenSourceIsUnknown() {
        let template = HyMTPromptBuilder.template(for: "今天天气真好，我们一起去公园散步吧。", source: nil, target: .english)
        #expect(template == .chinese)
    }

    @Test func japaneseSourceIsNotTreatedAsChinese() {
        let template = HyMTPromptBuilder.template(for: "今日はとても良い天気ですね。散歩に行きましょう。", source: nil, target: .english)
        #expect(template == .english)
    }

    @Test(arguments: HyMTLanguage.allCases)
    func everyLanguageHasBothNames(language: HyMTLanguage) {
        #expect(!language.englishName.isEmpty)
        #expect(!language.chineseName.isEmpty)
    }
}
