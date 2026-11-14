//
//  HyMTGenerationOptions.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation

/// Decoding parameters. `recommended` follows the official settings for Hy-MT2 1.8B / 7B.
public struct HyMTGenerationOptions: Equatable, Sendable {
    /// Sampling temperature; `0` selects greedy (deterministic) decoding.
    public var temperature: Float
    /// Number of highest-scoring tokens kept before sampling; `<= 0` keeps all tokens.
    public var topK: Int
    /// Nucleus sampling threshold in `(0, 1]`.
    public var topP: Float
    /// Penalty (> 1) applied to tokens already present in the prompt or output.
    public var repetitionPenalty: Float
    /// Upper bound on generated tokens; generation also stops at the model's context length.
    public var maxNewTokens: Int
    /// Seed for reproducible sampling; `nil` uses a random seed.
    public var seed: UInt64?

    public init(
        temperature: Float = 0.7,
        topK: Int = 20,
        topP: Float = 0.6,
        repetitionPenalty: Float = 1.05,
        maxNewTokens: Int = 512,
        seed: UInt64? = nil
    ) {
        self.temperature = temperature
        self.topK = topK
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.maxNewTokens = maxNewTokens
        self.seed = seed
    }

    /// Official recommendation: temperature 0.7, top-k 20, top-p 0.6, repetition penalty 1.05.
    public static let recommended = HyMTGenerationOptions()

    /// Greedy decoding without repetition penalty (stable output, useful for tests and caching).
    public static let greedy = HyMTGenerationOptions(temperature: 0, topK: 1, topP: 1, repetitionPenalty: 1)
}
