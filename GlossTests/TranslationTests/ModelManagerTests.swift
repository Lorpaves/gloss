//
//  ModelManagerTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import CryptoKit
import Testing
@testable import Gloss

@MainActor
struct ModelManagerTests {
    private let files = [
        ModelFile(name: "weights.gguf", size: 1_000, sha256: "", repository: .weights),
        ModelFile(name: "tokenizer.json", size: 200, sha256: "", repository: .tokenizer)
    ]

    // MARK: - Installation

    @Test func testFolderWithEveryFileAtFullSizeIsInstalled() throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try write(1_000, to: "weights.gguf", in: directory)
        try write(200, to: "tokenizer.json", in: directory)

        #expect(ModelManager.isInstalled(files, in: directory))
    }

    @Test func testFolderMissingAFileIsNotInstalled() throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try write(1_000, to: "weights.gguf", in: directory)

        #expect(!ModelManager.isInstalled(files, in: directory))
    }

    @Test func testFolderWithATruncatedFileIsNotInstalled() throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try write(999, to: "weights.gguf", in: directory)
        try write(200, to: "tokenizer.json", in: directory)

        #expect(!ModelManager.isInstalled(files, in: directory))
    }

    @Test func testBytesOnDiskCountsCompleteAndPartialFiles() throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try write(400, to: "weights.gguf.part", in: directory)
        try write(200, to: "tokenizer.json", in: directory)

        #expect(ModelManager.bytesOnDisk(of: files, in: directory) == 600)
    }

    @Test func testBytesOnDiskIgnoresWhatAFileHasTooMany() throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try write(5_000, to: "weights.gguf.part", in: directory)

        #expect(ModelManager.bytesOnDisk(of: files, in: directory) == 1_000)
    }

    // MARK: - Failures

    @Test func testNoConnectionIsReportedAsOffline() {
        #expect(ModelManager.failure(for: URLError(.notConnectedToInternet)) == .offline)
    }

    @Test func testDigestMismatchIsReportedAsCorrupted() {
        #expect(ModelManager.failure(for: ModelDownloadError.checksumMismatch) == .corrupted)
    }

    @Test func testServerErrorIsReportedAsServer() {
        #expect(ModelManager.failure(for: ModelDownloadError.httpStatus(500)) == .server)
    }

    @Test func testFullDiskIsReportedAsNotEnoughSpace() {
        #expect(ModelManager.failure(for: ModelDownloadError.insufficientSpace) == .notEnoughSpace)
        #expect(ModelManager.failure(for: POSIXError(.ENOSPC)) == .notEnoughSpace)
        #expect(ModelManager.failure(for: CocoaError(.fileWriteOutOfSpace)) == .notEnoughSpace)
    }

    @Test func testDroppedConnectionIsRetried() {
        #expect(ModelManager.isTransient(URLError(.networkConnectionLost)))
        #expect(ModelManager.isTransient(URLError(.timedOut)))
    }

    @Test func testBusyServerIsRetried() {
        #expect(ModelManager.isTransient(ModelDownloadError.httpStatus(503)))
        #expect(ModelManager.isTransient(ModelDownloadError.httpStatus(429)))
    }

    @Test func testMissingFileOnTheServerIsNotRetried() {
        #expect(!ModelManager.isTransient(ModelDownloadError.httpStatus(404)))
    }

    @Test func testBeingOfflineIsNotRetried() {
        #expect(!ModelManager.isTransient(URLError(.notConnectedToInternet)))
    }

    // MARK: - Downloading

    @Test func testDownloadInstallsEveryFile() async throws {
        let model = try makeModel()
        defer { model.cleanUp() }

        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        #expect(model.manager.isInstalled)
        #expect(try Data(contentsOf: model.directory.appending(path: "weights.gguf")) == Self.weights)
        #expect(try Data(contentsOf: model.directory.appending(path: "tokenizer.json")) == Self.tokenizer)
    }

    @Test func testBusyServerIsTriedAgainUntilItAnswers() async throws {
        let weights = Self.weights
        let model = try makeModel(retryDelays: [.milliseconds(1), .milliseconds(1)]) { request in
            StubURLProtocol.earlierAttempts(before: request) < 2 ? .init(status: 503) : .init(status: 200, body: weights)
        }
        defer { model.cleanUp() }

        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        #expect(model.manager.isInstalled)
        #expect(StubURLProtocol.requests(to: model.weightsURL).count == 3)
    }

    @Test func testDownloadFailsOnceTheRetriesRunOut() async throws {
        let model = try makeModel(retryDelays: [.milliseconds(1), .milliseconds(1)]) { _ in .init(status: 503) }
        defer { model.cleanUp() }

        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        #expect(model.manager.state == .downloadFailed(.server))
        #expect(StubURLProtocol.requests(to: model.weightsURL).count == 3)
    }

    @Test func testMissingFileFailsWithoutBeingTriedAgain() async throws {
        let model = try makeModel(retryDelays: [.milliseconds(1), .milliseconds(1)]) { _ in .init(status: 404) }
        defer { model.cleanUp() }

        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        #expect(model.manager.state == .downloadFailed(.server))
        #expect(StubURLProtocol.requests(to: model.weightsURL).count == 1)
    }

    @Test func testDamagedFileIsReportedAsCorruptedWithoutBeingTriedAgain() async throws {
        let damaged = Data(repeating: 1, count: Self.weights.count)
        let model = try makeModel(retryDelays: [.milliseconds(1)]) { _ in .init(status: 200, body: damaged) }
        defer { model.cleanUp() }

        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        #expect(model.manager.state == .downloadFailed(.corrupted))
        #expect(StubURLProtocol.requests(to: model.weightsURL).count == 1)
    }

    @Test func testDroppedConnectionIsRetriedFromWhereItStopped() async throws {
        let model = try makeModel(retryDelays: [.milliseconds(1)], weightsHandler: Self.droppingOnce)
        defer { model.cleanUp() }

        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        let requests = StubURLProtocol.requests(to: model.weightsURL)
        #expect(requests.count == 2)
        #expect(requests.last?.value(forHTTPHeaderField: "Range") == "bytes=20000-")
        #expect(try Data(contentsOf: model.directory.appending(path: "weights.gguf")) == Self.weights)
    }

    @Test func testDroppedConnectionWithNoRetriesLeftIsReportedAsOffline() async throws {
        let model = try makeModel(weightsHandler: Self.droppingOnce)
        defer { model.cleanUp() }

        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        #expect(model.manager.state == .downloadFailed(.offline))
    }

    @Test func testRetryingAFailedDownloadContinuesWhereItStopped() async throws {
        let model = try makeModel(weightsHandler: Self.droppingOnce)
        defer { model.cleanUp() }
        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        // What the Retry button does.
        model.manager.download(from: .huggingFace)
        await settle(model.manager)

        #expect(model.manager.isInstalled)
        #expect(StubURLProtocol.requests(to: model.weightsURL).last?.value(forHTTPHeaderField: "Range") == "bytes=20000-")
        #expect(try Data(contentsOf: model.directory.appending(path: "weights.gguf")) == Self.weights)
    }

    // MARK: - Private

    /// Not tied to the main actor: the stub server reads them from its own threads.
    private nonisolated static let weights = Data((0..<60_000).map { UInt8(truncatingIfNeeded: $0 &* 7) })
    private nonisolated static let tokenizer = Data(#"{"tokens":[]}"#.utf8)

    /// A server whose connection drops after the first 20,000 bytes of the weights, once; after that it serves
    /// whatever range it's asked for.
    private static let droppingOnce: StubURLProtocol.Handler = { request in
        let weights = ModelManagerTests.weights
        if StubURLProtocol.earlierAttempts(before: request) == 0 {
            return .init(status: 200, body: weights.prefix(20_000), failure: .networkConnectionLost)
        }
        guard request.value(forHTTPHeaderField: "Range") == "bytes=20000-" else {
            return .init(status: 200, body: weights)
        }
        return .init(
            status: 206,
            headers: ["Content-Range": "bytes 20000-59999/60000"],
            body: Data(weights.suffix(from: 20_000))
        )
    }

    private struct TestModel {
        let manager: ModelManager
        let directory: URL
        let weightsURL: URL
        let cleanUp: () -> Void
    }

    /// A manager over two small files served by the stub; the weights by `weightsHandler` if given.
    private func makeModel(
        retryDelays: [Duration] = [],
        weightsHandler: StubURLProtocol.Handler? = nil
    ) throws -> TestModel {
        let weights = Self.weights
        let tokenizer = Self.tokenizer
        let weightsURL = StubURLProtocol.register(weightsHandler ?? { _ in .init(status: 200, body: weights) })
        let tokenizerURL = StubURLProtocol.register { _ in .init(status: 200, body: tokenizer) }
        let root = FileManager.default.temporaryDirectory.appending(path: "ModelManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let directory = root.appending(path: "Model")
        let manager = ModelManager(
            directory: directory,
            engine: TranslationEngine(modelDirectory: directory),
            downloader: ModelDownloader(makeConfiguration: StubURLProtocol.configuration),
            files: [
                Self.file("weights.gguf", weights, in: .weights),
                Self.file("tokenizer.json", tokenizer, in: .tokenizer)
            ],
            retryDelays: retryDelays,
            locate: { file, _ in file.repository == .weights ? weightsURL : tokenizerURL }
        )
        return TestModel(manager: manager, directory: directory, weightsURL: weightsURL) {
            try? FileManager.default.removeItem(at: root)
        }
    }

    private static func file(_ name: String, _ contents: Data, in repository: ModelRepository) -> ModelFile {
        let digest = SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()
        return ModelFile(name: name, size: Int64(contents.count), sha256: digest, repository: repository)
    }

    /// Waits until the download and the load that follows it have ended, one way or the other. (The test files
    /// aren't a model, so a finished download ends as "couldn't load".)
    private func settle(_ manager: ModelManager) async {
        for _ in 0..<2_000 {
            switch manager.state {
            case .downloading, .verifying, .loading:
                try? await Task.sleep(for: .milliseconds(5))
            case .notDownloaded, .downloadFailed, .ready, .loadFailed:
                return
            }
        }
    }


    private func write(_ count: Int, to name: String, in directory: URL) throws {
        try Data(count: count).write(to: directory.appending(path: name))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ModelManagerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
