//
//  HyMTTranslationMetrics.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation

/// Timing and token counts of the most recent request (see ``HyMTTranslator/lastMetrics``).
public struct HyMTTranslationMetrics: Equatable, Sendable {
    /// Tokens in the prompt after applying the chat template.
    public let promptTokens: Int
    /// Tokens generated (excluding the end-of-turn token).
    public let generatedTokens: Int
    /// From request start until the first output token was chosen (tokenization + prompt prefill).
    public let timeToFirstToken: Duration
    /// From request start until generation finished.
    public let totalDuration: Duration

    /// Output tokens per second after the first token (pure decode speed).
    public var decodeTokensPerSecond: Double {
        let decodeSeconds = Self.seconds(totalDuration - timeToFirstToken)
        guard generatedTokens > 1, decodeSeconds > 0 else { return 0 }
        return Double(generatedTokens - 1) / decodeSeconds
    }

    /// Prompt tokens processed per second until the first output token.
    public var promptTokensPerSecond: Double {
        let seconds = Self.seconds(timeToFirstToken)
        return seconds > 0 ? Double(promptTokens) / seconds : 0
    }

    public init(promptTokens: Int, generatedTokens: Int, timeToFirstToken: Duration, totalDuration: Duration) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.timeToFirstToken = timeToFirstToken
        self.totalDuration = totalDuration
    }

    private static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
