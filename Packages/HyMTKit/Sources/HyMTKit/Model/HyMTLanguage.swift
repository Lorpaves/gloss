//
//  HyMTLanguage.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation

/// Languages supported by Hy-MT2 (see the model card's "Supported Languages" table).
public enum HyMTLanguage: String, CaseIterable, Codable, Sendable {
    case chinese = "zh"
    case english = "en"
    case french = "fr"
    case portuguese = "pt"
    case spanish = "es"
    case japanese = "ja"
    case turkish = "tr"
    case russian = "ru"
    case arabic = "ar"
    case korean = "ko"
    case thai = "th"
    case italian = "it"
    case german = "de"
    case vietnamese = "vi"
    case malay = "ms"
    case indonesian = "id"
    case filipino = "tl"
    case hindi = "hi"
    case traditionalChinese = "zh-Hant"
    case polish = "pl"
    case czech = "cs"
    case dutch = "nl"
    case khmer = "km"
    case burmese = "my"
    case persian = "fa"
    case gujarati = "gu"
    case urdu = "ur"
    case telugu = "te"
    case marathi = "mr"
    case hebrew = "he"
    case bengali = "bn"
    case tamil = "ta"
    case ukrainian = "uk"
    case tibetan = "bo"
    case kazakh = "kk"
    case mongolian = "mn"
    case uyghur = "ug"
    case cantonese = "yue"

    // MARK: - Properties

    /// Full English name, used inside English prompt templates.
    public var englishName: String { names.english }

    /// Full Chinese name, used inside Chinese prompt templates.
    public var chineseName: String { names.chinese }

    /// Chinese varieties select the Chinese prompt template.
    public var isChineseVariety: Bool {
        self == .chinese || self == .traditionalChinese || self == .cantonese
    }

    // MARK: - Private

    private var names: (english: String, chinese: String) {
        switch self {
        case .chinese: ("Chinese", "中文")
        case .english: ("English", "英语")
        case .french: ("French", "法语")
        case .portuguese: ("Portuguese", "葡萄牙语")
        case .spanish: ("Spanish", "西班牙语")
        case .japanese: ("Japanese", "日语")
        case .turkish: ("Turkish", "土耳其语")
        case .russian: ("Russian", "俄语")
        case .arabic: ("Arabic", "阿拉伯语")
        case .korean: ("Korean", "韩语")
        case .thai: ("Thai", "泰语")
        case .italian: ("Italian", "意大利语")
        case .german: ("German", "德语")
        case .vietnamese: ("Vietnamese", "越南语")
        case .malay: ("Malay", "马来语")
        case .indonesian: ("Indonesian", "印尼语")
        case .filipino: ("Filipino", "菲律宾语")
        case .hindi: ("Hindi", "印地语")
        case .traditionalChinese: ("Traditional Chinese", "繁体中文")
        case .polish: ("Polish", "波兰语")
        case .czech: ("Czech", "捷克语")
        case .dutch: ("Dutch", "荷兰语")
        case .khmer: ("Khmer", "高棉语")
        case .burmese: ("Burmese", "缅甸语")
        case .persian: ("Persian", "波斯语")
        case .gujarati: ("Gujarati", "古吉拉特语")
        case .urdu: ("Urdu", "乌尔都语")
        case .telugu: ("Telugu", "泰卢固语")
        case .marathi: ("Marathi", "马拉地语")
        case .hebrew: ("Hebrew", "希伯来语")
        case .bengali: ("Bengali", "孟加拉语")
        case .tamil: ("Tamil", "泰米尔语")
        case .ukrainian: ("Ukrainian", "乌克兰语")
        case .tibetan: ("Tibetan", "藏语")
        case .kazakh: ("Kazakh", "哈萨克语")
        case .mongolian: ("Mongolian", "蒙古语")
        case .uyghur: ("Uyghur", "维吾尔语")
        case .cantonese: ("Cantonese", "粤语")
        }
    }
}
