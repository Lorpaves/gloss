//
//  ModelRepository.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// The two repositories Tencent publishes the model in, under the same names in every source.
internal enum ModelRepository: Equatable, Sendable {
    /// `Hy-MT2-1.8B-GGUF`: the quantized weights.
    case weights
    /// `Hy-MT2-1.8B`: the tokenizer and configuration files.
    case tokenizer
}
