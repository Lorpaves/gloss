//
//  HyMTPromptBuilder.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation
import NaturalLanguage

/// Builds the official Hy-MT2 "default translation" prompts.
///
/// Template choice follows the Hy-MT convention: translations involving Chinese (as source or target) use the
/// Chinese template with Chinese language names; all other pairs use the English template with English names.
internal enum HyMTPromptBuilder {
    internal enum Template: Equatable {
        case chinese
        case english
    }

    /// - Parameters:
    ///   - text: Source text.
    ///   - source: Source language, or `nil` to detect whether the text is Chinese.
    ///   - target: Target language.
    /// - Returns: The user message to send through the chat template.
    internal static func prompt(for text: String, source: HyMTLanguage?, target: HyMTLanguage) -> String {
        switch template(for: text, source: source, target: target) {
        case .chinese:
            "将以下文本翻译为\(target.chineseName)，注意只需要输出翻译后的结果，不要额外解释：\n\n\(text)"
        case .english:
            "Translate the following text into \(target.englishName). Note that you should only output the translated result without any additional explanation:\n\n\(text)"
        }
    }

    internal static func template(for text: String, source: HyMTLanguage?, target: HyMTLanguage) -> Template {
        if target.isChineseVariety {
            return .chinese
        }
        if let source {
            return source.isChineseVariety ? .chinese : .english
        }
        return isChinese(text) ? .chinese : .english
    }

    // MARK: - Private

    private static func isChinese(_ text: String) -> Bool {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let language = recognizer.dominantLanguage else { return false }
        return language == .simplifiedChinese || language == .traditionalChinese
    }
}
