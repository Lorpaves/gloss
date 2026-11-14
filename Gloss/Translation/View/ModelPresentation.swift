//
//  ModelPresentation.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

// MARK: - ModelDownloadFailure

extension ModelDownloadFailure {
    /// What Settings and the welcome guide say about the failure, localized.
    internal var message: String {
        switch self {
        case .offline:
            String(localized: "无法连接服务器")
        case .notEnoughSpace:
            String(localized: "磁盘空间不足")
        case .corrupted:
            String(localized: "文件校验失败")
        case .server:
            String(localized: "服务器出错")
        case .other:
            String(localized: "下载失败")
        }
    }
}

// MARK: - ModelSource

extension ModelSource {
    /// The source's name in pickers, localized.
    internal var title: String {
        switch self {
        case .huggingFace:
            "Hugging Face"
        case .modelScope:
            String(localized: "ModelScope（魔搭）")
        }
    }
}

// MARK: - ModelProgressFormat

/// How download progress is written out.
internal enum ModelProgressFormat {
    /// "512 MB / 1.14 GB".
    internal static func bytes(received: Int64, total: Int64) -> String {
        let style = ByteCountFormatStyle(style: .file)
        return "\(received.formatted(style)) / \(total.formatted(style))"
    }

    /// Share of the download done, from 0 to 1.
    internal static func fraction(received: Int64, total: Int64) -> Double {
        total > 0 ? min(Double(received) / Double(total), 1) : 0
    }
}
