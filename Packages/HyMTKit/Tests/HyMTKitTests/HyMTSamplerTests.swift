//
//  HyMTSamplerTests.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation
import Testing
@testable import HyMTKit

struct HyMTSamplerTests {
    @Test func greedyPicksHighestScore() {
        let sampler = HyMTSampler(options: .greedy)
        var generator = HyMTRandomGenerator(seed: 1)
        #expect(sampler.sample(logits: [0.1, 3.0, -2.0, 2.9], penalizedTokens: [], using: &generator) == 1)
    }

    @Test func repetitionPenaltyDemotesSeenToken() {
        var options = HyMTGenerationOptions.greedy
        options.repetitionPenalty = 1.05
        let sampler = HyMTSampler(options: options)
        var generator = HyMTRandomGenerator(seed: 1)
        // 2.0 / 1.05 = 1.905 < 1.95
        #expect(sampler.sample(logits: [2.0, 1.95], penalizedTokens: [0], using: &generator) == 1)
    }

    @Test func negativeScoresArePenalizedByMultiplication() {
        var options = HyMTGenerationOptions.greedy
        options.repetitionPenalty = 2
        let sampler = HyMTSampler(options: options)
        var generator = HyMTRandomGenerator(seed: 1)
        // -1.0 * 2 = -2.0 < -1.5
        #expect(sampler.sample(logits: [-1.0, -1.5], penalizedTokens: [0], using: &generator) == 1)
    }

    @Test func topPKeepsOnlyDominantToken() {
        let options = HyMTGenerationOptions(temperature: 1, topK: 20, topP: 0.6, repetitionPenalty: 1)
        let sampler = HyMTSampler(options: options)
        var generator = HyMTRandomGenerator(seed: 7)
        var logits = [Float](repeating: 0, count: 1_000)
        logits[42] = 8 // ~0.75 probability mass on its own
        for _ in 0..<200 {
            #expect(sampler.sample(logits: logits, penalizedTokens: [], using: &generator) == 42)
        }
    }

    @Test func topKRestrictsCandidates() {
        let options = HyMTGenerationOptions(temperature: 1, topK: 2, topP: 1, repetitionPenalty: 1)
        let sampler = HyMTSampler(options: options)
        var generator = HyMTRandomGenerator(seed: 3)
        let logits: [Float] = [1.0, 1.1, 0.9, 1.05, 0.95]
        for _ in 0..<200 {
            let token = sampler.sample(logits: logits, penalizedTokens: [], using: &generator)
            #expect(token == 1 || token == 3)
        }
    }

    @Test func sameSeedReproducesSameSequence() {
        let sampler = HyMTSampler(options: HyMTGenerationOptions(temperature: 1, topK: 50, topP: 1, repetitionPenalty: 1))
        let logits = (0..<500).map { Float(($0 * 7919) % 97) / 20 }
        var first = HyMTRandomGenerator(seed: 2026)
        var second = HyMTRandomGenerator(seed: 2026)
        let a = (0..<50).map { _ in sampler.sample(logits: logits, penalizedTokens: [], using: &first) }
        let b = (0..<50).map { _ in sampler.sample(logits: logits, penalizedTokens: [], using: &second) }
        #expect(a == b)
        #expect(Set(a).count > 1)
    }
}
