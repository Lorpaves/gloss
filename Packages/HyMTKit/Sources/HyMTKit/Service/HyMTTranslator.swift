//
//  HyMTTranslator.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation
import os
import Tokenizers

/// On-device Hy-MT2 translator backed by llama.cpp (GGUF model, Metal GPU; iOS 18+ / macOS 15+).
///
/// One instance owns the loaded model. Requests on the same instance run one at a time in FIFO order: a request
/// that arrives while another is generating (or a cancelled one is still winding down) waits for it to finish.
/// ```swift
/// let translator = try await HyMTTranslator(modelURL: ggufURL, tokenizerDirectory: directoryURL)
/// let english = try await translator.translate("今天天气真好", to: .english)
/// ```
public actor HyMTTranslator {
    // MARK: - Properties

    /// Maximum number of tokens (prompt + output) per request.
    public nonisolated let contextLength: Int

    /// Whether the model runs on the GPU (what ``HyMTComputeUnits/automatic`` resolved to on this device).
    public nonisolated let usesGPU: Bool

    /// Timing and token counts of the most recent completed request; `nil` until one finishes.
    public private(set) var lastMetrics: HyMTTranslationMetrics?

    private let decoder: HyMTDecoder
    private let tokenizer: any Tokenizer
    private let stopTokenIds: Set<Int>

    /// Whether a generation currently owns the decoder's single llama.cpp context.
    private var isGenerating = false
    /// Generations waiting for the context, oldest first.
    private var generationWaiters: [CheckedContinuation<Void, Never>] = []

    /// `<｜hy_place▁holder▁no▁2｜>`, the end-of-turn token in `generation_config.json`.
    private static let endOfTurnTokenId = 120_020
    /// Same window as the former Core ML model; the KV cache costs 64 KB per token.
    private static let defaultContextLength = 1024
    private static let logger = Logger(subsystem: "HyMTKit", category: "HyMTTranslator")

    // MARK: - Lifecycle

    /// Loads the GGUF model with llama.cpp and the tokenizer.
    /// - Parameters:
    ///   - modelURL: `.gguf` file, e.g. the official `Hy-MT2-1.8B-Q4_K_M.gguf` from `tencent/Hy-MT2-1.8B-GGUF`.
    ///   - tokenizerDirectory: Folder with `tokenizer.json`, `tokenizer_config.json` and `chat_template.jinja` from
    ///     `tencent/Hy-MT2-1.8B` (token ids match the GGUF vocabulary).
    ///   - computeUnits: `.automatic` (default) picks the GPU on A14 / M1 and later and the CPU on older chips.
    /// - Note: Loading takes a few seconds; create one instance and reuse it.
    public init(
        modelURL: URL,
        tokenizerDirectory: URL,
        computeUnits: HyMTComputeUnits = .automatic
    ) async throws {
        let decoder = try HyMTDecoder.load(
            modelURL: modelURL,
            computeUnits: computeUnits,
            contextLength: Self.defaultContextLength
        )
        guard decoder.vocabularySize > Self.endOfTurnTokenId else {
            throw HyMTError.unsupportedModel(reason: "vocabulary of \(decoder.vocabularySize) tokens is not Hy-MT2's")
        }
        let tokenizer = try await AutoTokenizer.from(modelFolder: tokenizerDirectory)

        var stops: Set<Int> = [Self.endOfTurnTokenId]
        if let eos = tokenizer.eosTokenId {
            stops.insert(eos)
        }
        self.decoder = decoder
        self.tokenizer = tokenizer
        self.stopTokenIds = stops
        self.contextLength = decoder.contextLength
        self.usesGPU = decoder.usesGPU
    }

    // MARK: - Translation

    /// Translates `text` into `target`.
    /// - Parameters:
    ///   - text: Source text.
    ///   - target: Target language.
    ///   - source: Source language if known; only used to pick the prompt template (auto-detected otherwise).
    ///   - options: Decoding options; defaults to the official recommendation.
    /// - Returns: The translated text.
    public func translate(
        _ text: String,
        to target: HyMTLanguage,
        from source: HyMTLanguage? = nil,
        options: HyMTGenerationOptions = .recommended
    ) async throws -> String {
        let prompt = HyMTPromptBuilder.prompt(for: text, source: source, target: target)
        return try await generate(prompt: prompt, options: options, onPartial: nil)
    }

    /// Streams a translation. Each element is the full text decoded so far; cancelling the consuming task
    /// stops generation.
    public nonisolated func translationStream(
        _ text: String,
        to target: HyMTLanguage,
        from source: HyMTLanguage? = nil,
        options: HyMTGenerationOptions = .recommended
    ) -> AsyncThrowingStream<String, Error> {
        let prompt = HyMTPromptBuilder.prompt(for: text, source: source, target: target)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await self.generate(prompt: prompt, options: options) { partial in
                        continuation.yield(partial)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Runs a caller-built prompt, e.g. the terminology / style / structured-data templates from the model card.
    /// - Parameters:
    ///   - prompt: The user message (the chat template is applied automatically).
    ///   - options: Decoding options.
    /// - Returns: The generated text.
    public func complete(prompt: String, options: HyMTGenerationOptions = .recommended) async throws -> String {
        try await generate(prompt: prompt, options: options, onPartial: nil)
    }

    // MARK: - Private

    private func generate(
        prompt: String,
        options: HyMTGenerationOptions,
        onPartial: (@Sendable (String) -> Void)?
    ) async throws -> String {
        // The loop below suspends at `Task.yield()`, which lets other requests onto the actor. They all share one
        // KV cache (`makeSession()` clears it), so a request must not start until the previous one has finished.
        await acquireGeneration()
        defer { releaseGeneration() }
        try Task.checkCancellation()

        let clock = ContinuousClock()
        let start = clock.now
        let messages: [Message] = [["role": "user", "content": prompt]]
        let promptIds = try tokenizer.applyChatTemplate(messages: messages)
        guard promptIds.count < contextLength else {
            throw HyMTError.inputTooLong(promptTokens: promptIds.count, contextLength: contextLength)
        }

        let session = try decoder.makeSession()
        var logits = try session.consume(prompt: promptIds) { try Task.checkCancellation() }

        let sampler = HyMTSampler(options: options)
        var generator = HyMTRandomGenerator(seed: options.seed)
        var seen = Set(promptIds)
        var output: [Int] = []
        var firstToken: ContinuousClock.Instant?
        while output.count < options.maxNewTokens {
            try Task.checkCancellation()
            let next = sampler.sample(logits: logits, penalizedTokens: seen, using: &generator)
            if firstToken == nil {
                firstToken = clock.now
            }
            if stopTokenIds.contains(next) {
                break
            }
            output.append(next)
            seen.insert(next)
            if let onPartial {
                let partial = tokenizer.decode(tokens: output, skipSpecialTokens: true)
                // Skip states that end inside a multi-byte character.
                if !partial.hasSuffix("\u{FFFD}") {
                    onPartial(partial)
                }
            }
            guard session.position < contextLength else {
                Self.logger.notice("Context window (\(self.contextLength)) exhausted; output truncated")
                break
            }
            logits = try session.feed(next)
            await Task.yield()
        }
        let end = clock.now
        lastMetrics = HyMTTranslationMetrics(
            promptTokens: promptIds.count,
            generatedTokens: output.count,
            timeToFirstToken: (firstToken ?? end) - start,
            totalDuration: end - start
        )
        return tokenizer.decode(tokens: output, skipSpecialTokens: true)
    }

    /// Waits until no other generation is running, then claims the decoder.
    private func acquireGeneration() async {
        guard isGenerating else {
            isGenerating = true
            return
        }
        await withCheckedContinuation { continuation in
            generationWaiters.append(continuation)
        }
    }

    /// Hands the decoder to the oldest waiting generation, or marks it idle.
    private func releaseGeneration() {
        if generationWaiters.isEmpty {
            isGenerating = false
        } else {
            generationWaiters.removeFirst().resume()
        }
    }
}
