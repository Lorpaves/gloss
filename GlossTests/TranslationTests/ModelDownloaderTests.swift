//
//  ModelDownloaderTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import Testing
import CryptoKit
import Synchronization
@testable import Gloss

/// Runs the downloader against ``StubURLProtocol`` instead of the network.
struct ModelDownloaderTests {
    private let body = Data((0..<100_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
    private let downloader = ModelDownloader(makeConfiguration: StubURLProtocol.configuration)

    // MARK: - Downloading

    @Test func testDownloadsAMissingFile() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        let body = body
        let url = StubURLProtocol.register { _ in .init(status: 200, body: body) }

        try await downloader.fetch(file, from: url, into: directory) { _ in }

        #expect(try Data(contentsOf: directory.appending(path: file.name)) == body)
    }

    @Test func testRemovesThePartialFileOnceComplete() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        let body = body
        let url = StubURLProtocol.register { _ in .init(status: 200, body: body) }

        try await downloader.fetch(file, from: url, into: directory) { _ in }

        #expect(!FileManager.default.fileExists(atPath: partialURL(in: directory).path))
    }

    @Test func testContinuesAPartialFileWithARangeRequest() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try body.prefix(40_000).write(to: partialURL(in: directory))
        let rest = body.suffix(from: 40_000)
        let url = StubURLProtocol.register { _ in
            .init(status: 206, headers: ["Content-Range": "bytes 40000-99999/100000"], body: Data(rest))
        }

        try await downloader.fetch(file, from: url, into: directory) { _ in }

        #expect(StubURLProtocol.requests(to: url).first?.value(forHTTPHeaderField: "Range") == "bytes=40000-")
        #expect(try Data(contentsOf: directory.appending(path: file.name)) == body)
    }

    @Test func testStartsOverWhenTheServerIgnoresTheRange() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try Data(repeating: 0xFF, count: 40_000).write(to: partialURL(in: directory))
        let body = body
        let url = StubURLProtocol.register { _ in .init(status: 200, body: body) }

        try await downloader.fetch(file, from: url, into: directory) { _ in }

        #expect(try Data(contentsOf: directory.appending(path: file.name)) == body)
    }

    @Test func testKeepsAnIntactFileWithoutDownloadingIt() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        try body.write(to: directory.appending(path: file.name))
        let url = StubURLProtocol.register { _ in .init(status: 500) }

        try await downloader.fetch(file, from: url, into: directory) { _ in }

        #expect(StubURLProtocol.requests(to: url).isEmpty)
    }

    @Test func testRejectsAFileThatDoesNotMatchItsDigest() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        let damaged = Data(repeating: 1, count: body.count)
        let url = StubURLProtocol.register { _ in .init(status: 200, body: damaged) }

        await #expect(throws: ModelDownloadError.checksumMismatch) {
            try await downloader.fetch(file, from: url, into: directory) { _ in }
        }
    }

    @Test func testDeletesAFileThatDoesNotMatchItsDigest() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        let damaged = Data(repeating: 1, count: body.count)
        let url = StubURLProtocol.register { _ in .init(status: 200, body: damaged) }

        _ = try? await downloader.fetch(file, from: url, into: directory) { _ in }

        #expect(!FileManager.default.fileExists(atPath: partialURL(in: directory).path))
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: file.name).path))
    }

    @Test func testReportsTheStatusOfAnErrorResponse() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        let url = StubURLProtocol.register { _ in .init(status: 404) }

        await #expect(throws: ModelDownloadError.httpStatus(404)) {
            try await downloader.fetch(file, from: url, into: directory) { _ in }
        }
    }

    @Test func testReportsTheWholeFileAsReceivedAtTheEnd() async throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        let body = body
        let url = StubURLProtocol.register { _ in .init(status: 200, body: body) }
        let events = Mutex<[ModelDownloader.Event]>([])

        try await downloader.fetch(file, from: url, into: directory) { event in
            events.withLock { $0.append(event) }
        }

        #expect(events.withLock { $0.last } == .received(Int64(body.count)))
    }

    // MARK: - Helpers

    @Test func testDigestMatchesTheKnownDigestOfABC() throws {
        let directory = try makeDirectory()
        defer { remove(directory) }
        let url = directory.appending(path: "abc.txt")
        try Data("abc".utf8).write(to: url)

        #expect(try ModelDownloader.sha256(of: url) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    @Test func testContentRangeStartIsItsFirstByte() {
        #expect(ModelDownloader.rangeStart(ofContentRange: "bytes 40000-99999/100000") == 40_000)
    }

    @Test func testContentRangeWithoutAStartHasNone() {
        #expect(ModelDownloader.rangeStart(ofContentRange: "bytes */100000") == nil)
        #expect(ModelDownloader.rangeStart(ofContentRange: nil) == nil)
    }

    // MARK: - Private

    private var file: ModelFile {
        let digest = SHA256.hash(data: body).map { String(format: "%02x", $0) }.joined()
        return ModelFile(name: "model.bin", size: Int64(body.count), sha256: digest, repository: .weights)
    }

    private func partialURL(in directory: URL) -> URL {
        directory.appending(path: file.name + ".part")
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(path: "ModelDownloaderTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func remove(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
    }
}
