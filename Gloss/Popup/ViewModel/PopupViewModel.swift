//
//  PopupViewModel.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import Observation
import os
import HyMTKit

/// State of the translation popup. Owns the task that consumes the translation stream.
@MainActor
@Observable
internal final class PopupViewModel {
    /// What the popup shows.
    internal enum Phase: Equatable, Sendable {
        /// Waiting for the model or the first words.
        case waiting
        case translating
        case finished
        case failed
        case tooLong
    }

    // MARK: - Properties

    internal private(set) var translation = ""
    internal private(set) var phase: Phase = .waiting
    /// A pinned popup ignores outside clicks and Esc, and stays in place for new selections.
    internal var isPinned = false
    /// Tallest the popup may get at its current position.
    internal var maxHeight: CGFloat = PopupLayout.maximumHeight
    /// The selection being shown; selecting the same text again doesn't restart the translation.
    internal private(set) var sourceText = ""
    /// Increases with every new selection, so the view reports its size even when it happens to be unchanged.
    internal private(set) var generation = 0

    @ObservationIgnored private let engine: TranslationEngine
    @ObservationIgnored private var translationTask: Task<Void, Never>?

    private static let logger = Logger.gloss("PopupViewModel")

    // MARK: - Lifecycle

    internal init(engine: TranslationEngine) {
        self.engine = engine
    }

    // MARK: - Actions

    /// Starts translating a selection, replacing whatever the popup showed.
    internal func translate(_ text: String, from source: HyMTLanguage, to target: HyMTLanguage) {
        cancel()
        sourceText = text
        translation = ""
        phase = .waiting
        generation += 1
        translationTask = Task { [weak self, engine] in
            let clock = ContinuousClock()
            let start = clock.now
            do {
                for try await partial in engine.translationStream(text, from: source, to: target) {
                    // A newer selection may have replaced this one; its partials must not overwrite the popup.
                    guard !Task.isCancelled else { return }
                    self?.translation = partial
                    self?.phase = .translating
                }
                guard !Task.isCancelled else { return }
                self?.phase = .finished
                Self.logger.debug("Translated \(text.count) characters in \(clock.now - start, privacy: .public)")
            } catch is CancellationError {
                // Replaced by a newer selection or the popup closed.
                return
            } catch {
                guard !Task.isCancelled else { return }
                Self.logger.error("Translation failed: \(error.localizedDescription, privacy: .public)")
                self?.phase = .failed
            }
        }
    }

    /// Shows "text too long" instead of translating.
    internal func showTooLong(_ text: String) {
        cancel()
        sourceText = text
        translation = ""
        phase = .tooLong
        generation += 1
    }

    /// Stops the running translation.
    internal func cancel() {
        translationTask?.cancel()
        translationTask = nil
    }

    /// Puts the translation on the clipboard (writing never triggers the paste privacy alert).
    internal func copyTranslation() {
        guard !translation.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(translation, forType: .string)
    }
}
