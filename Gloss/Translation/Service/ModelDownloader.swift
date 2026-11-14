//
//  ModelDownloader.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import CryptoKit
import Synchronization

/// Downloads files of the translation model over HTTP and checks each against its SHA-256 digest.
///
/// A file is first written as `<name>.part`; a later attempt continues it with an HTTP range request, so a stopped or
/// failed download picks up where it ended, also after a relaunch. The file only gets its final name once it matches
/// its digest.
internal struct ModelDownloader: Sendable {
    /// Progress of one file.
    internal enum Event: Equatable, Sendable {
        /// This many bytes of the file are on disk.
        case received(Int64)
        /// The file is complete and being checked against its digest.
        case verifying
    }

    // MARK: - Properties

    private let makeConfiguration: @Sendable () -> URLSessionConfiguration

    /// Files from this size up report ``Event/verifying``; smaller ones are checked in an instant.
    private static let verificationReportThreshold: Int64 = 64 << 20
    private static let readChunkSize = 4 << 20

    // MARK: - Lifecycle

    /// - Parameter makeConfiguration: Configuration of the session each download runs in; tests swap the network
    ///   for a stub through it.
    internal init(makeConfiguration: @escaping @Sendable () -> URLSessionConfiguration = Self.defaultConfiguration) {
        self.makeConfiguration = makeConfiguration
    }

    /// An ephemeral session that gives up after a minute without data instead of waiting for a connection.
    internal static func defaultConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }

    // MARK: - Downloading

    /// Makes sure `directory` holds an intact `file`, downloading from `url` whatever is missing.
    /// - Parameters:
    ///   - onEvent: Called with the progress, from any thread, at most about ten times a second.
    /// - Throws: ``ModelDownloadError``, `URLError` or a file system error, and `CancellationError` when cancelled.
    ///   A file that fails its check is deleted, so the next attempt starts it over.
    internal func fetch(
        _ file: ModelFile,
        from url: URL,
        into directory: URL,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async throws {
        let fileManager = FileManager.default
        let target = directory.appending(path: file.name)
        let partial = directory.appending(path: file.name + ".part")

        if fileManager.fileExists(atPath: target.path) {
            if try Self.isIntact(target, as: file, onEvent: onEvent) {
                onEvent(.received(file.size))
                return
            }
            try fileManager.removeItem(at: target)
        }

        var offset = Self.size(of: partial) ?? 0
        if offset > file.size {
            try fileManager.removeItem(at: partial)
            offset = 0
        }
        if offset < file.size {
            do {
                try await download(url, into: partial, from: offset, onEvent: onEvent)
            } catch ModelDownloadError.rangeNotSatisfiable, ModelDownloadError.unexpectedRange {
                // What's on disk doesn't line up with the file on the server: start over.
                try fileManager.removeItem(at: partial)
                try await download(url, into: partial, from: 0, onEvent: onEvent)
            }
        }

        guard try Self.isIntact(partial, as: file, onEvent: onEvent) else {
            try? fileManager.removeItem(at: partial)
            throw ModelDownloadError.checksumMismatch
        }
        try fileManager.moveItem(at: partial, to: target)
    }

    // MARK: - Helpers

    /// SHA-256 digest of a file's contents, in lowercase hex.
    /// - Throws: A file system error, or `CancellationError` when the calling task is cancelled.
    internal static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: readChunkSize, alignment: 16)
        defer { buffer.deallocate() }
        var hasher = SHA256()
        while true {
            try Task.checkCancellation()
            let count = read(handle.fileDescriptor, buffer.baseAddress, buffer.count)
            if count < 0 {
                if errno == EINTR {
                    continue
                }
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            if count == 0 {
                break
            }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[..<count]))
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The first byte a `Content-Range` header (`bytes 100-199/200`) covers.
    internal static func rangeStart(ofContentRange header: String?) -> Int64? {
        guard let header, header.hasPrefix("bytes ") else { return nil }
        let range = header.dropFirst("bytes ".count)
        guard let dash = range.firstIndex(of: "-") else { return nil }
        return Int64(range[..<dash])
    }

    /// Size of the file at `url`, or `nil` when there is none.
    internal static func size(of url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber
        else { return nil }
        return size.int64Value
    }

    // MARK: - Private

    /// Whether the file at `url` has `file`'s size and digest.
    private static func isIntact(
        _ url: URL,
        as file: ModelFile,
        onEvent: @Sendable (Event) -> Void
    ) throws -> Bool {
        guard size(of: url) == file.size else { return false }
        if file.size >= verificationReportThreshold {
            onEvent(.verifying)
        }
        return try sha256(of: url) == file.sha256
    }

    /// Appends the body of `url`, from byte `offset` on, to `partial`.
    private func download(
        _ url: URL,
        into partial: URL,
        from offset: Int64,
        onEvent: @escaping @Sendable (Event) -> Void
    ) async throws {
        var request = URLRequest(url: url)
        if offset > 0 {
            request.setValue("bytes=\(offset)-", forHTTPHeaderField: "Range")
        }
        let writer = PartialFileWriter(file: partial, offset: offset, onEvent: onEvent)
        let session = URLSession(configuration: makeConfiguration(), delegate: writer, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let task = session.dataTask(with: request)
        do {
            try await withTaskCancellationHandler {
                try await writer.run(task)
            } onCancel: {
                task.cancel()
            }
        } catch {
            // Cancelling the task makes it fail with `URLError.cancelled`.
            if Task.isCancelled {
                throw CancellationError()
            }
            throw error
        }
    }
}

// MARK: - PartialFileWriter

/// Receives one response and writes its body into a partial file, reporting how much of the file is on disk.
private final class PartialFileWriter: NSObject, URLSessionDataDelegate, Sendable {
    private struct State {
        var handle: FileHandle?
        /// Bytes of the file on disk.
        var written: Int64
        var lastReport: ContinuousClock.Instant?
        /// Why the response was refused or writing stopped; takes precedence over the task's own error.
        var failure: (any Error)?
        var continuation: CheckedContinuation<Void, any Error>?
    }

    private let file: URL
    private let offset: Int64
    private let onEvent: @Sendable (ModelDownloader.Event) -> Void
    private let state: Mutex<State>

    private static let reportInterval = Duration.milliseconds(100)

    init(file: URL, offset: Int64, onEvent: @escaping @Sendable (ModelDownloader.Event) -> Void) {
        self.file = file
        self.offset = offset
        self.onEvent = onEvent
        state = Mutex(State(written: offset))
        super.init()
    }

    /// Starts `task` and returns once its response is written.
    func run(_ task: URLSessionDataTask) async throws {
        try await withCheckedThrowingContinuation { continuation in
            state.withLock { $0.continuation = continuation }
            task.resume()
        }
    }

    // MARK: - URLSessionDataDelegate

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        do {
            let handle = try open(for: response)
            state.withLock { $0.handle = handle }
            completionHandler(.allow)
        } catch {
            state.withLock { $0.failure = error }
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        let outcome: WriteOutcome = state.withLock { state in
            guard let handle = state.handle, state.failure == nil else { return .stopped }
            do {
                try handle.write(contentsOf: data)
            } catch {
                state.failure = error
                return .failed
            }
            state.written += Int64(data.count)
            let now = ContinuousClock.now
            if let lastReport = state.lastReport, now - lastReport < Self.reportInterval {
                return .written
            }
            state.lastReport = now
            return .report(state.written)
        }
        switch outcome {
        case .report(let written):
            onEvent(.received(written))
        case .failed:
            dataTask.cancel()
        case .written, .stopped:
            break
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Sources redirect to their CDNs; the range has to come along.
        var request = request
        if request.value(forHTTPHeaderField: "Range") == nil,
           let range = task.originalRequest?.value(forHTTPHeaderField: "Range") {
            request.setValue(range, forHTTPHeaderField: "Range")
        }
        completionHandler(request)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?) {
        let (continuation, failure, written) = state.withLock { state in
            try? state.handle?.close()
            state.handle = nil
            let continuation = state.continuation
            state.continuation = nil
            return (continuation, state.failure ?? error, state.written)
        }
        if let failure {
            continuation?.resume(throwing: failure)
        } else {
            onEvent(.received(written))
            continuation?.resume()
        }
    }

    // MARK: - Private

    private enum WriteOutcome {
        case written
        case report(Int64)
        case failed
        case stopped
    }

    /// Opens the partial file at the byte the response starts with.
    private func open(for response: URLResponse) throws -> FileHandle {
        guard let response = response as? HTTPURLResponse else {
            throw ModelDownloadError.httpStatus(0)
        }
        let start: Int64
        switch response.statusCode {
        case 200:
            // The whole file, so whatever was on disk is replaced.
            start = 0
        case 206:
            let rangeStart = ModelDownloader.rangeStart(ofContentRange: response.value(forHTTPHeaderField: "Content-Range"))
            guard rangeStart == offset else { throw ModelDownloadError.unexpectedRange }
            start = offset
        case 416:
            throw ModelDownloadError.rangeNotSatisfiable
        default:
            throw ModelDownloadError.httpStatus(response.statusCode)
        }
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: file.path), !fileManager.createFile(atPath: file.path, contents: nil) {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: file.path])
        }
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: UInt64(start))
        try handle.seek(toOffset: UInt64(start))
        state.withLock { $0.written = start }
        return handle
    }
}
