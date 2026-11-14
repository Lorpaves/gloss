//
//  HyMTDecoder.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation
import os
import Synchronization
import llama

/// Runs the Hy-MT2 GGUF model with llama.cpp (Metal on Apple GPUs) and returns raw logits to ``HyMTTranslator``.
///
/// The llama.cpp context holds one sequence; ``makeSession()`` starts over with an empty KV cache.
/// Not thread-safe: owned and used exclusively by ``HyMTTranslator``.
internal final class HyMTDecoder {
    // MARK: - Properties

    internal let contextLength: Int
    internal let vocabularySize: Int
    /// Whether the layers run on the GPU (resolved from ``HyMTComputeUnits``).
    internal let usesGPU: Bool

    private let resources: HyMTLlamaResources

    /// Prompt tokens per `llama_decode` call; cancellation is checked between calls.
    fileprivate static let promptChunkTokens = 512
    /// Memory needed on top of the model file: KV cache, Metal compute buffers and the app itself.
    private static let memoryHeadroomMB = 512

    fileprivate static let logger = Logger(subsystem: "HyMTKit", category: "HyMTDecoder")

    /// Initializes the llama.cpp backends once and routes their warnings to the unified log instead of stderr.
    private static let backend: Void = {
        llama_log_set({ level, text, _ in
            guard let text, level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR else { return }
            let message = String(cString: text).trimmingCharacters(in: .whitespacesAndNewlines)
            HyMTDecoder.logger.notice("llama.cpp: \(message, privacy: .public)")
        }, nil)
        llama_backend_init()
    }()

    // MARK: - Lifecycle

    private init(resources: HyMTLlamaResources, contextLength: Int, vocabularySize: Int, usesGPU: Bool) {
        self.resources = resources
        self.contextLength = contextLength
        self.vocabularySize = vocabularySize
        self.usesGPU = usesGPU
    }

    deinit {
        resources.free()
    }

    /// Loads a GGUF model and creates its context.
    /// - Parameters:
    ///   - url: `.gguf` file.
    ///   - computeUnits: Automatic, GPU (every layer through Metal) or CPU only.
    ///   - contextLength: Maximum tokens per sequence (prompt + output).
    /// - Returns: The decoder.
    internal static func load(modelURL url: URL, computeUnits: HyMTComputeUnits, contextLength: Int) throws -> HyMTDecoder {
        _ = backend
        try checkAvailableMemory(forModelAt: url)

        let usesGPU = computeUnits.usesGPU
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = usesGPU ? -1 : 0
        guard let model = llama_model_load_from_file(url.path, modelParams) else {
            throw HyMTError.unsupportedModel(reason: "llama.cpp could not load \(url.lastPathComponent)")
        }

        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32(contextLength)
        contextParams.n_batch = UInt32(contextLength)
        contextParams.n_seq_max = 1
        let threads = Int32(performanceCoreCount())
        contextParams.n_threads = threads
        contextParams.n_threads_batch = threads
        if !usesGPU {
            // Keep the KV cache and large batch matmuls off the GPU as well.
            contextParams.offload_kqv = false
            contextParams.op_offload = false
        }
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw HyMTError.unsupportedModel(reason: "llama.cpp could not create a context for \(url.lastPathComponent)")
        }
        let vocabularySize = Int(llama_vocab_n_tokens(llama_model_get_vocab(model)))
        let resources = HyMTLlamaResources(
            model: model,
            context: context,
            batch: llama_batch_init(Int32(contextLength), 0, 1)
        )
        logger.notice("Loaded \(url.lastPathComponent, privacy: .public) on the \(usesGPU ? "GPU" : "CPU", privacy: .public) (\(String(describing: computeUnits), privacy: .public)): vocab \(vocabularySize), context \(contextLength), \(threads) threads")
        return HyMTDecoder(resources: resources, contextLength: contextLength, vocabularySize: vocabularySize, usesGPU: usesGPU)
    }

    // MARK: - Session

    /// Starts a new sequence with an empty KV cache.
    internal func makeSession() throws -> HyMTDecoderSession {
        try resources.withLive { live in
            llama_memory_clear(llama_get_memory(live.context), false)
        }
        return HyMTDecoderSession(decoder: self)
    }

    /// Runs `tokens` at positions `start ..< start + tokens.count`.
    /// - Returns: The logits after the last token when `wantsLogits` is set, otherwise `nil`.
    fileprivate func decode(_ tokens: ArraySlice<Int>, start: Int, wantsLogits: Bool) throws -> [Float]? {
        let vocabularySize = vocabularySize
        return try resources.withLive { live in
            live.batch.n_tokens = Int32(tokens.count)
            for (offset, token) in tokens.enumerated() {
                live.batch.token[offset] = llama_token(token)
                live.batch.pos[offset] = llama_pos(start + offset)
                live.batch.n_seq_id[offset] = 1
                live.batch.seq_id[offset]?.pointee = 0
                live.batch.logits[offset] = 0
            }
            if wantsLogits {
                live.batch.logits[tokens.count - 1] = 1
            }
            let status = llama_decode(live.context, live.batch)
            guard status == 0 else {
                HyMTDecoder.logger.error("llama_decode failed with status \(status)")
                throw HyMTError.decodeFailed(status: Int(status))
            }
            guard wantsLogits else { return nil }
            guard let logits = llama_get_logits_ith(live.context, -1) else {
                throw HyMTError.invalidOutput
            }
            return Array(UnsafeBufferPointer(start: logits, count: vocabularySize))
        }
    }

    // MARK: - Private

    /// A llama.cpp / Metal crash on the memory limit cannot be caught, so refuse up front on devices that are too small.
    private static func checkAvailableMemory(forModelAt url: URL) throws {
        #if (os(iOS) || os(tvOS) || os(visionOS)) && !targetEnvironment(simulator)
        let available = Int(os_proc_available_memory() / 1_048_576)
        guard available > 0 else { return }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else {
            logger.notice("Could not read the size of \(url.lastPathComponent, privacy: .public); skipping memory check")
            return
        }
        let required = size / 1_048_576 + memoryHeadroomMB
        if available < required {
            logger.error("Not enough memory to load the model: \(available) MB available, \(required) MB required")
            throw HyMTError.insufficientMemory(availableMB: available, requiredMB: required)
        }
        #endif
    }

    /// Performance cores on Apple silicon; half the logical CPUs elsewhere (Intel Macs report hyper-threads).
    private static func performanceCoreCount() -> Int {
        var count: Int32 = 0
        var size = MemoryLayout<Int32>.size
        if sysctlbyname("hw.perflevel0.physicalcpu", &count, &size, nil, 0) == 0, count > 0 {
            return Int(count)
        }
        return max(1, ProcessInfo.processInfo.activeProcessorCount / 2)
    }
}

/// One generation sequence on the decoder's llama.cpp context.
internal final class HyMTDecoderSession {
    // MARK: - Properties

    internal private(set) var position = 0

    private let decoder: HyMTDecoder

    // MARK: - Lifecycle

    fileprivate init(decoder: HyMTDecoder) {
        self.decoder = decoder
    }

    // MARK: - Decoding

    /// Feeds the whole prompt (in chunks of up to 512 tokens) and returns the logits for the first generated token.
    /// - Parameters:
    ///   - tokens: Prompt token ids (non-empty).
    ///   - checkCancellation: Called between llama.cpp calls; throw to abort.
    /// - Returns: Logits over the vocabulary.
    internal func consume(prompt tokens: [Int], checkCancellation: () throws -> Void) throws -> [Float] {
        guard !tokens.isEmpty else { throw HyMTError.emptyInput }
        guard position + tokens.count <= decoder.contextLength else {
            throw HyMTError.contextExhausted(contextLength: decoder.contextLength)
        }
        var logits: [Float]?
        var index = 0
        while index < tokens.count {
            try checkCancellation()
            let end = min(index + HyMTDecoder.promptChunkTokens, tokens.count)
            logits = try decoder.decode(tokens[index..<end], start: position, wantsLogits: end == tokens.count)
            position += end - index
            index = end
        }
        guard let logits else { throw HyMTError.invalidOutput }
        return logits
    }

    /// Appends `token` at the next position and returns the logits for the token that follows it.
    internal func feed(_ token: Int) throws -> [Float] {
        guard position < decoder.contextLength else {
            throw HyMTError.contextExhausted(contextLength: decoder.contextLength)
        }
        guard let logits = try decoder.decode([token][...], start: position, wantsLogits: true) else {
            throw HyMTError.invalidOutput
        }
        position += 1
        return logits
    }
}

/// The llama.cpp objects of one loaded model, freed exactly once: by the decoder's deinit, or at process exit.
///
/// ggml's Metal backend asserts in a C++ static destructor that every model and context is gone, so a process that
/// calls `exit()` (e.g. a Mac app quitting with ⌘Q) while a model is loaded would abort. An `atexit` handler,
/// registered after the first model load and therefore run before that destructor, frees whatever is still alive.
/// Every llama.cpp call holds the lock, so the handler waits for an in-flight `llama_decode` before freeing.
private final class HyMTLlamaResources: Sendable {
    // MARK: - Types

    /// Raw llama.cpp pointers; only ever touched inside `live`'s lock, which is what makes them safe to share.
    struct Live: @unchecked Sendable {
        let model: OpaquePointer
        let context: OpaquePointer
        var batch: llama_batch
    }

    // MARK: - Properties

    private let live: Mutex<Live?>

    private static let registry = Mutex<[ObjectIdentifier: HyMTLlamaResources]>([:])
    private static let exitHandler: Void = {
        atexit { HyMTLlamaResources.freeAll() }
    }()

    // MARK: - Lifecycle

    init(model: OpaquePointer, context: OpaquePointer, batch: llama_batch) {
        live = Mutex(Live(model: model, context: context, batch: batch))
        _ = Self.exitHandler
        Self.registry.withLock { $0[ObjectIdentifier(self)] = self }
    }

    // MARK: - Access

    /// Runs `body` with the live llama.cpp objects under the lock.
    /// - Throws: ``HyMTError/modelUnloaded`` once the objects were freed (the process is exiting).
    func withLive<Result>(_ body: (inout Live) throws -> Result) throws -> Result {
        try live.withLock { live throws -> Result in
            guard var current = live else { throw HyMTError.modelUnloaded }
            defer { live = current }
            return try body(&current)
        }
    }

    /// Frees the llama.cpp objects (idempotent).
    func free() {
        live.withLock { live in
            guard let current = live else { return }
            llama_batch_free(current.batch)
            llama_free(current.context)
            llama_model_free(current.model)
            live = nil
        }
        _ = Self.registry.withLock { $0.removeValue(forKey: ObjectIdentifier(self)) }
    }

    // MARK: - Private

    private static func freeAll() {
        let all = registry.withLock { Array($0.values) }
        for resources in all {
            resources.free()
        }
    }
}
