//
//  HyMTSampler.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation

/// Next-token selection: repetition penalty -> temperature -> top-k -> top-p (same order as transformers).
internal struct HyMTSampler {
    internal let options: HyMTGenerationOptions

    // MARK: - Sampling

    /// - Parameters:
    ///   - logits: Raw scores for every vocabulary entry.
    ///   - penalizedTokens: Tokens already present in prompt or output (repetition penalty targets).
    ///   - generator: Random source; only used when sampling (temperature > 0).
    /// - Returns: The selected token id.
    internal func sample<G: RandomNumberGenerator>(
        logits: [Float],
        penalizedTokens: Set<Int>,
        using generator: inout G
    ) -> Int {
        var scores = logits
        let penalty = options.repetitionPenalty
        if penalty != 1 {
            for token in penalizedTokens where scores.indices.contains(token) {
                let score = scores[token]
                scores[token] = score > 0 ? score / penalty : score * penalty
            }
        }

        if options.temperature <= 0 || options.topK == 1 {
            return Self.argmax(scores)
        }

        // Candidates sorted by score, best first.
        let k = options.topK > 0 ? min(options.topK, scores.count) : scores.count
        let candidates = Self.topK(scores, k: k)
        guard let best = candidates.first else { return Self.argmax(scores) }

        // Softmax with temperature over the candidates.
        let temperature = options.temperature
        var probabilities = candidates.map { expf((scores[$0] - scores[best]) / temperature) }
        let total = probabilities.reduce(0, +)
        probabilities = probabilities.map { $0 / total }

        // Nucleus: keep the smallest prefix whose cumulative probability reaches top-p.
        var keep = probabilities.count
        if options.topP < 1 {
            var cumulative: Float = 0
            for (index, probability) in probabilities.enumerated() {
                cumulative += probability
                if cumulative >= options.topP {
                    keep = index + 1
                    break
                }
            }
        }

        let kept = probabilities.prefix(keep)
        let threshold = Float.random(in: 0..<kept.reduce(0, +), using: &generator)
        var cumulative: Float = 0
        for (index, probability) in kept.enumerated() {
            cumulative += probability
            if threshold < cumulative {
                return candidates[index]
            }
        }
        return candidates[keep - 1]
    }

    // MARK: - Private

    private static func argmax(_ scores: [Float]) -> Int {
        var best = 0
        var bestScore = -Float.infinity
        for (index, score) in scores.enumerated() where score > bestScore {
            best = index
            bestScore = score
        }
        return best
    }

    /// Indices of the `k` largest scores, best first. O(n * k), cheap for the small k used in decoding.
    private static func topK(_ scores: [Float], k: Int) -> [Int] {
        guard k < scores.count / 8 else {
            return scores.indices.sorted { scores[$0] > scores[$1] }.prefix(k).map { $0 }
        }
        var top: [Int] = []
        top.reserveCapacity(k + 1)
        for (index, score) in scores.enumerated() {
            if top.count == k, let last = top.last, score <= scores[last] {
                continue
            }
            let position = top.firstIndex { score > scores[$0] } ?? top.count
            top.insert(index, at: position)
            if top.count > k {
                top.removeLast()
            }
        }
        return top
    }
}

/// SplitMix64: small, fast and seedable, so sampling can be reproduced from `HyMTGenerationOptions.seed`.
internal struct HyMTRandomGenerator: RandomNumberGenerator {
    private var state: UInt64

    internal init(seed: UInt64?) {
        state = seed ?? UInt64.random(in: .min ... .max)
    }

    internal mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
