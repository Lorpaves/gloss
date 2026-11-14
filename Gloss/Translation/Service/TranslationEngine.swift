//
//  TranslationEngine.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import os
import HyMTKit

/// Errors thrown by ``TranslationEngine``.
internal enum TranslationEngineError: Error {
    /// The model hasn't been downloaded.
    case modelMissing
}

/// Owns the Hy-MT2 model and streams translations of selections, segment by segment.
internal actor TranslationEngine {
    // MARK: - Properties

    private let modelDirectory: URL
    private var loadTask: Task<HyMTTranslator, Error>?

    /// How many times a segment that is still too long for the model gets halved.
    private static let maximumSplitDepth = 2
    private static let logger = Logger.gloss("TranslationEngine")

    // MARK: - Lifecycle

    /// - Parameter modelDirectory: Folder with the GGUF model and tokenizer files (see ``ModelManifest``).
    internal init(modelDirectory: URL) {
        self.modelDirectory = modelDirectory
    }

    // MARK: - Model

    /// Loads the model, unless it's loaded already.
    internal func prepare() async throws {
        _ = try await translator()
    }

    /// Lets go of the loaded model; the next translation loads it again.
    internal func unload() {
        loadTask = nil
    }

    /// The loaded translator. The first call starts loading; concurrent callers share that load, and a cancelled
    /// caller doesn't abort it. After a failure the next call tries again.
    internal func translator() async throws -> HyMTTranslator {
        let task = loadTask ?? makeLoadTask()
        loadTask = task
        do {
            return try await task.value
        } catch {
            // Another caller may already have started a retry.
            if loadTask == task {
                loadTask = nil
            }
            throw error
        }
    }

    // MARK: - Translation

    /// Streams the translation of a selection; each element is the whole translation so far.
    ///
    /// Long text is translated in segments (see ``TextSegmenter``). Cancelling the consuming task stops
    /// generation; HyMTKit runs requests one at a time, so the next translation starts once this one has stopped.
    internal nonisolated func translationStream(
        _ text: String,
        from source: HyMTLanguage,
        to target: HyMTLanguage
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let translator = try await self.translator()
                    let segments = TextSegmenter.segments(of: text)
                    var finished: [String] = []
                    for segment in segments {
                        try Task.checkCancellation()
                        let done = finished
                        let translated = try await Self.translate(
                            segment.text,
                            depth: 0,
                            translator: translator,
                            source: source,
                            target: target
                        ) { partial in
                            continuation.yield(TextSegmenter.join(done + [partial], segments: segments, target: target))
                        }
                        finished.append(translated)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Private

    private func makeLoadTask() -> Task<HyMTTranslator, Error> {
        let directory = modelDirectory
        return Task.detached(priority: .userInitiated) {
            let weights = directory.appending(path: ModelManifest.weightsFileName)
            guard FileManager.default.fileExists(atPath: weights.path) else {
                Self.logger.error("No model at \(directory.path, privacy: .public)")
                throw TranslationEngineError.modelMissing
            }
            let clock = ContinuousClock()
            let start = clock.now
            do {
                let translator = try await HyMTTranslator(
                    modelURL: weights,
                    tokenizerDirectory: directory
                )
                let device = translator.usesGPU ? "GPU" : "CPU"
                Self.logger.notice("Model loaded in \(clock.now - start, privacy: .public) on the \(device, privacy: .public)")
                return translator
            } catch {
                Self.logger.error("Model failed to load: \(error.localizedDescription, privacy: .public)")
                throw error
            }
        }
    }

    /// Translates one segment, halving it when the model reports the prompt as too long.
    private static func translate(
        _ text: String,
        depth: Int,
        translator: HyMTTranslator,
        source: HyMTLanguage,
        target: HyMTLanguage,
        onPartial: (String) -> Void
    ) async throws -> String {
        do {
            var latest = ""
            for try await partial in translator.translationStream(text, to: target, from: source) {
                latest = partial
                onPartial(partial)
            }
            // The stream also ends quietly when this task is cancelled.
            try Task.checkCancellation()
            return latest
        } catch let error as HyMTError {
            guard case .inputTooLong(let promptTokens, _) = error,
                  depth < maximumSplitDepth,
                  let halves = TextSegmenter.halves(of: text)
            else { throw error }
            logger.debug("Segment of \(promptTokens) prompt tokens doesn't fit; translating it in halves")
            let separator = TextSegmenter.separator(for: target)
            let first = try await translate(
                halves.0, depth: depth + 1, translator: translator, source: source, target: target
            ) { partial in
                onPartial(partial)
            }
            let second = try await translate(
                halves.1, depth: depth + 1, translator: translator, source: source, target: target
            ) { partial in
                onPartial(first + separator + partial)
            }
            return first + separator + second
        }
    }
}
