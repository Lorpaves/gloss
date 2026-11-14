//
//  ModelManager.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import AppKit
import Observation
import os

/// Downloads, installs and loads the translation model, which isn't part of the app (it's 1.1 GB).
///
/// The download goes into a staging folder next to the installed model and is moved into place once every file
/// matches its digest, so the installed folder is always complete.
@MainActor
@Observable
internal final class ModelManager {
    // MARK: - Properties

    internal private(set) var state: ModelState

    /// Where the model is installed.
    internal let directory: URL

    @ObservationIgnored private let engine: TranslationEngine
    @ObservationIgnored private let downloader: ModelDownloader
    @ObservationIgnored private let files: [ModelFile]
    @ObservationIgnored private let retryDelays: [Duration]
    @ObservationIgnored private let locate: @Sendable (ModelFile, ModelSource) -> URL
    @ObservationIgnored private var downloadTask: Task<Void, Never>?
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Waits before trying a file again after a network failure; the retry continues where the failure stopped it.
    internal static let defaultRetryDelays: [Duration] = [.seconds(2), .seconds(5), .seconds(10)]
    /// Room to leave on the disk besides the model.
    private static let spaceMargin: Int64 = 256 << 20
    private static let logger = Logger.gloss("ModelManager")

    // MARK: - Lifecycle

    /// - Parameters:
    ///   - directory: Where the model is installed, usually ``ModelManifest/installDirectory``.
    ///   - engine: Loads the installed model.
    ///   - files: The model's files; tests pass small ones.
    ///   - retryDelays: Waits before each automatic retry of a file; none means no automatic retries.
    ///   - locate: Download URL of a file in a source.
    internal init(
        directory: URL,
        engine: TranslationEngine,
        downloader: ModelDownloader,
        files: [ModelFile] = ModelManifest.files,
        retryDelays: [Duration] = ModelManager.defaultRetryDelays,
        locate: @escaping @Sendable (ModelFile, ModelSource) -> URL = ModelManifest.url(of:in:)
    ) {
        self.directory = directory
        self.engine = engine
        self.downloader = downloader
        self.files = files
        self.retryDelays = retryDelays
        self.locate = locate
        state = Self.isInstalled(files, in: directory) ? .loading : .notDownloaded
    }

    // MARK: - Queries

    /// Whether selections can be translated: the model is loaded, or about to be.
    internal var acceptsSelections: Bool {
        state == .loading || state == .ready
    }

    /// Whether the model has yet to be downloaded.
    internal var needsDownload: Bool {
        switch state {
        case .notDownloaded, .downloadFailed:
            true
        case .downloading, .verifying, .loading, .ready, .loadFailed:
            false
        }
    }

    /// Whether the model is on this Mac.
    internal var isInstalled: Bool {
        switch state {
        case .loading, .ready, .loadFailed:
            true
        case .notDownloaded, .downloading, .verifying, .downloadFailed:
            false
        }
    }

    // MARK: - Actions

    /// Loads the model if it's installed; call once at launch.
    internal func start() {
        if state == .loading {
            load()
        }
    }

    /// Downloads and installs the model, then loads it. Continues a download that was stopped earlier.
    internal func download(from source: ModelSource) {
        guard needsDownload, downloadTask == nil else { return }
        state = .downloading(received: 0, total: totalSize)
        downloadTask = Task { [weak self] in
            await self?.performDownload(from: source)
        }
    }

    /// Stops the download; what it got stays on disk for the next one.
    internal func cancelDownload() {
        downloadTask?.cancel()
    }

    internal func retryLoad() {
        guard state == .loadFailed else { return }
        load()
    }

    /// Deletes the installed model and any partial download, and unloads the model.
    internal func delete() {
        guard downloadTask == nil else { return }
        let fileManager = FileManager.default
        for url in [directory, stagingDirectory] where fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                Self.logger.error("Couldn't delete \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        guard !Self.isInstalled(files, in: directory) else { return }
        loadTask?.cancel()
        loadTask = nil
        state = .notDownloaded
        Task { [engine] in
            await engine.unload()
        }
        Self.logger.notice("Model deleted")
    }

    /// Shows the installed model in Finder.
    internal func revealInFinder() {
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    // MARK: - Helpers

    /// Whether `directory` holds all `files` at their full size. Digests are checked when the files are downloaded,
    /// not at every launch.
    internal static func isInstalled(_ files: [ModelFile], in directory: URL) -> Bool {
        files.allSatisfy { ModelDownloader.size(of: directory.appending(path: $0.name)) == $0.size }
    }

    /// How much of `files` a download in `directory` already has, complete or partial.
    internal static func bytesOnDisk(of files: [ModelFile], in directory: URL) -> Int64 {
        files.reduce(0) { total, file in
            let complete = ModelDownloader.size(of: directory.appending(path: file.name))
            let partial = ModelDownloader.size(of: directory.appending(path: file.name + ".part"))
            return total + min(complete ?? partial ?? 0, file.size)
        }
    }

    /// What to tell the user about a download error.
    internal static func failure(for error: any Error) -> ModelDownloadFailure {
        if let error = error as? ModelDownloadError {
            switch error {
            case .checksumMismatch:
                return .corrupted
            case .insufficientSpace:
                return .notEnoughSpace
            case .httpStatus, .unexpectedRange, .rangeNotSatisfiable:
                return .server
            }
        }
        if let error = error as? URLError {
            switch error.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost,
                 .dnsLookupFailed, .timedOut, .secureConnectionFailed, .internationalRoamingOff, .dataNotAllowed:
                return .offline
            default:
                return .other
            }
        }
        let error = error as NSError
        if (error.domain == NSPOSIXErrorDomain && error.code == Int(ENOSPC))
            || (error.domain == NSCocoaErrorDomain && error.code == NSFileWriteOutOfSpaceError) {
            return .notEnoughSpace
        }
        return .other
    }

    /// Whether trying again soon may get past `error`: a dropped or slow connection, or a busy server.
    internal static func isTransient(_ error: any Error) -> Bool {
        if let error = error as? URLError {
            return [.networkConnectionLost, .timedOut, .cannotConnectToHost].contains(error.code)
        }
        if case .httpStatus(let status) = error as? ModelDownloadError {
            return status == 429 || (500...599).contains(status)
        }
        return false
    }

    // MARK: - Private: downloading

    /// The download's working folder, moved into place when complete.
    private var stagingDirectory: URL {
        directory.deletingLastPathComponent().appending(
            path: directory.lastPathComponent + ".download",
            directoryHint: .isDirectory
        )
    }

    private var totalSize: Int64 {
        files.reduce(0) { $0 + $1.size }
    }

    private func performDownload(from source: ModelSource) async {
        // Cleared together with the final state, so a retry right after a failure isn't turned away.
        defer { downloadTask = nil }
        let total = totalSize
        do {
            try prepareStagingDirectory()
            let onDisk = Self.bytesOnDisk(of: files, in: stagingDirectory)
            state = .downloading(received: onDisk, total: total)
            try checkSpace(needed: total - onDisk)
            Self.logger.notice("Downloading the model from \(source.rawValue, privacy: .public), \(onDisk) bytes on disk")
            var completed: Int64 = 0
            for file in files {
                try await fetch(file, from: source, completedBefore: completed)
                completed += file.size
            }
            try install()
            Self.logger.notice("Model downloaded and installed")
            load()
        } catch {
            if Task.isCancelled || error is CancellationError {
                Self.logger.notice("Model download stopped")
                state = .notDownloaded
            } else {
                Self.logger.error("Model download failed: \(String(describing: error), privacy: .public)")
                state = .downloadFailed(Self.failure(for: error))
            }
        }
    }

    /// Creates the staging folder, and moves the files of a damaged installation into it so intact ones are kept.
    private func prepareStagingDirectory() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        for file in files {
            let installed = directory.appending(path: file.name)
            let staged = stagingDirectory.appending(path: file.name)
            if fileManager.fileExists(atPath: installed.path), !fileManager.fileExists(atPath: staged.path) {
                try fileManager.moveItem(at: installed, to: staged)
            }
        }
        try fileManager.removeItem(at: directory)
    }

    private func checkSpace(needed: Int64) throws {
        let values = try stagingDirectory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values.volumeAvailableCapacityForImportantUsage, available < needed + Self.spaceMargin {
            throw ModelDownloadError.insufficientSpace
        }
    }

    /// Downloads one file, trying again a few times when the connection drops.
    private func fetch(_ file: ModelFile, from source: ModelSource, completedBefore completed: Int64) async throws {
        let url = locate(file, source)
        var delays = retryDelays[...]
        while true {
            do {
                try await fetchOnce(file, from: url, completedBefore: completed)
                return
            } catch let error where !Task.isCancelled && Self.isTransient(error) {
                guard let delay = delays.popFirst() else { throw error }
                Self.logger.notice("Retrying \(file.name, privacy: .public) in \(delay): \(String(describing: error), privacy: .public)")
                try await Task.sleep(for: delay)
            }
        }
    }

    private func fetchOnce(_ file: ModelFile, from url: URL, completedBefore completed: Int64) async throws {
        // Only the latest progress matters; older reports are dropped rather than queued up.
        let (events, continuation) = AsyncStream.makeStream(
            of: ModelDownloader.Event.self,
            bufferingPolicy: .bufferingNewest(1)
        )
        async let fetching: Void = Self.runFetch(
            file,
            from: url,
            into: stagingDirectory,
            downloader: downloader,
            continuation: continuation
        )
        for await event in events {
            switch event {
            case .received(let bytes):
                state = .downloading(received: completed + bytes, total: totalSize)
            case .verifying:
                state = .verifying
            }
        }
        try await fetching
    }

    /// Runs the download off the main actor, passing its progress on.
    private nonisolated static func runFetch(
        _ file: ModelFile,
        from url: URL,
        into directory: URL,
        downloader: ModelDownloader,
        continuation: AsyncStream<ModelDownloader.Event>.Continuation
    ) async throws {
        defer { continuation.finish() }
        try await downloader.fetch(file, from: url, into: directory) { event in
            continuation.yield(event)
        }
    }

    /// Moves the complete download into place.
    private func install() throws {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        try fileManager.moveItem(at: stagingDirectory, to: directory)
    }

    // MARK: - Private: loading

    private func load() {
        state = .loading
        loadTask?.cancel()
        loadTask = Task { [weak self, engine] in
            do {
                try await engine.prepare()
                guard !Task.isCancelled else { return }
                self?.state = .ready
            } catch {
                // The engine logs the cause.
                guard !Task.isCancelled else { return }
                self?.state = .loadFailed
            }
        }
    }
}
