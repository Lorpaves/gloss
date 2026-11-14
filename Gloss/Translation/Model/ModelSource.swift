//
//  ModelSource.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// Where the translation model is downloaded from. Both host Tencent's official files, byte for byte the same.
internal enum ModelSource: String, CaseIterable, Codable, Sendable {
    case huggingFace
    /// ModelScope (魔搭社区), reachable from mainland China.
    case modelScope
}
