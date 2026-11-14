//
//  HyMTError.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation

/// Errors thrown by ``HyMTTranslator``.
public enum HyMTError: Error, Equatable, Sendable {
    /// llama.cpp could not load the GGUF model or create its context, or the model does not match the tokenizer.
    case unsupportedModel(reason: String)
    /// The prompt does not fit into the model's context window.
    case inputTooLong(promptTokens: Int, contextLength: Int)
    /// The KV cache is full; no more tokens can be fed.
    case contextExhausted(contextLength: Int)
    /// The prompt produced no tokens.
    case emptyInput
    /// The device cannot load the model within the app's memory limit.
    case insufficientMemory(availableMB: Int, requiredMB: Int)
    /// llama.cpp returned no logits for the last token.
    case invalidOutput
    /// `llama_decode` failed (1: no KV slot, 2: aborted, negative: invalid batch or fatal error).
    case decodeFailed(status: Int)
    /// The model was already released because the process is exiting.
    case modelUnloaded
}

extension HyMTError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedModel(let reason):
            "Unsupported Hy-MT model: \(reason)"
        case .inputTooLong(let promptTokens, let contextLength):
            "Input is too long (\(promptTokens) prompt tokens, context length \(contextLength))."
        case .contextExhausted(let contextLength):
            "Context window of \(contextLength) tokens is exhausted."
        case .emptyInput:
            "The prompt is empty."
        case .insufficientMemory(let availableMB, let requiredMB):
            "Not enough memory to load the model on this device (\(availableMB) MB available, \(requiredMB) MB required)."
        case .invalidOutput:
            "The model returned no usable logits."
        case .decodeFailed(let status):
            "llama.cpp failed to run the model (status \(status))."
        case .modelUnloaded:
            "The model was released because the app is exiting."
        }
    }
}
