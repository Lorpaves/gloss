//
//  HyMTTranslatorTests.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/12.
//

import Foundation
import Testing
@testable import HyMTKit

/// End-to-end tests against the real model. Enabled only when `HYMT_MODEL_DIR` points to a folder containing
/// the GGUF model (`*.gguf`) plus the tokenizer files.
enum TestModel {
    static let directory: URL? = ProcessInfo.processInfo.environment["HYMT_MODEL_DIR"]
        .map { URL(fileURLWithPath: $0, isDirectory: true) }

    /// Loaded once and shared by all tests (the model is ~1 GB).
    static let shared = Task { () throws -> HyMTTranslator in
        guard let directory else { throw HyMTError.unsupportedModel(reason: "HYMT_MODEL_DIR not set") }
        return try await HyMTTranslator(modelURL: modelURL(), tokenizerDirectory: directory)
    }

    static func modelURL() throws -> URL {
        guard let directory else { throw HyMTError.unsupportedModel(reason: "HYMT_MODEL_DIR not set") }
        let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        guard let url = contents.first(where: { $0.pathExtension == "gguf" }) else {
            throw HyMTError.unsupportedModel(reason: "no model in \(directory.path)")
        }
        return url
    }
}

@Suite(.serialized, .enabled(if: TestModel.directory != nil))
struct HyMTTranslatorTests {
    @Test func translatesChineseToEnglish() async throws {
        let translator = try await TestModel.shared.value
        let result = try await translator.translate("今天天气真好，我们一起去公园散步吧。", to: .english, options: .greedy)
        #expect(result.localizedCaseInsensitiveContains("weather"))
        #expect(result.localizedCaseInsensitiveContains("park"))
    }

    @Test func translatesEnglishToChinese() async throws {
        let translator = try await TestModel.shared.value
        let result = try await translator.translate(
            "The quick brown fox jumps over the lazy dog.", to: .chinese, from: .english, options: .greedy
        )
        #expect(result.contains("狐狸"))
    }

    @Test func streamEndsWithSameTextAsTranslate() async throws {
        let translator = try await TestModel.shared.value
        let text = "这款应用支持离线翻译，保护您的隐私。"
        let expected = try await translator.translate(text, to: .japanese, options: .greedy)

        var partials: [String] = []
        for try await partial in translator.translationStream(text, to: .japanese, options: .greedy) {
            partials.append(partial)
        }
        #expect(partials.count > 1)
        #expect(partials.last == expected)
    }

    @Test func sampledTranslationIsReproducibleWithSeed() async throws {
        let translator = try await TestModel.shared.value
        var options = HyMTGenerationOptions.recommended
        options.seed = 42
        let text = "On-device translation keeps your data private."
        let first = try await translator.translate(text, to: .german, from: .english, options: options)
        let second = try await translator.translate(text, to: .german, from: .english, options: options)
        #expect(first == second)
        #expect(!first.isEmpty)
    }

    @Test func batchedPromptMatchesTokenByTokenFeeding() async throws {
        let decoder = try HyMTDecoder.load(modelURL: TestModel.modelURL(), computeUnits: .gpu, contextLength: 1024)
        // More than one 512-token prompt chunk.
        let tokens = (0..<600).map { 1_000 + ($0 * 7_919) % 90_000 }

        let batched = try decoder.makeSession().consume(prompt: tokens) {}
        let sequential = try decoder.makeSession()
        var reference: [Float] = []
        for token in tokens {
            reference = try sequential.feed(token)
        }
        #expect(Self.argmax(batched) == Self.argmax(reference))
        let maxDifference = zip(batched, reference).map { abs($0 - $1) }.max() ?? .infinity
        #expect(maxDifference < 0.5)
    }

    @Test(.timeLimit(.minutes(10)))
    func cpuOnlyTranslationIsCorrect() async throws {
        let directory = try #require(TestModel.directory)
        let translator = try await HyMTTranslator(
            modelURL: TestModel.modelURL(),
            tokenizerDirectory: directory,
            computeUnits: .cpuOnly
        )
        let result = try await translator.translate("今天天气真好，我们一起去公园散步吧。", to: .english, options: .greedy)
        #expect(result.localizedCaseInsensitiveContains("weather"))
    }

    @Test func overlappingRequestsMatchSequentialOutput() async throws {
        let translator = try await TestModel.shared.value
        let chinese = "今天天气真好，我们一起去公园散步吧。"
        let english = "The quick brown fox jumps over the lazy dog."
        let expectedEnglish = try await translator.translate(chinese, to: .english, options: .greedy)
        let expectedChinese = try await translator.translate(english, to: .chinese, from: .english, options: .greedy)

        async let first = translator.translate(chinese, to: .english, options: .greedy)
        async let second = translator.translate(english, to: .chinese, from: .english, options: .greedy)
        let (firstResult, secondResult) = try await (first, second)

        #expect(firstResult == expectedEnglish)
        #expect(secondResult == expectedChinese)
    }

    @Test func cancelledStreamDoesNotCorruptNextRequest() async throws {
        let translator = try await TestModel.shared.value
        let text = "On-device translation keeps your data private."
        let expected = try await translator.translate(text, to: .chinese, from: .english, options: .greedy)

        // Cancel before the stream has started generating, and while it is generating.
        for delay in [Duration.zero, .milliseconds(150)] {
            let consumer = Task {
                for try await _ in translator.translationStream(Self.longChinese, to: .english, options: .greedy) {}
            }
            try await Task.sleep(for: delay)
            consumer.cancel()
            let result = try await translator.translate(text, to: .chinese, from: .english, options: .greedy)
            #expect(result == expected)
        }
    }

    @Test func rejectsInputLongerThanContext() async throws {
        let translator = try await TestModel.shared.value
        let longText = String(repeating: "这是一个很长的句子。", count: 600)
        await #expect(throws: HyMTError.self) {
            _ = try await translator.translate(longText, to: .english)
        }
    }

    private static let longChinese = """
        这款应用支持离线翻译，所有内容都只在本机处理，不会上传到任何服务器。\
        我们希望它在每一台设备上都运行得又快又稳，即使在没有网络的飞机上也能随时使用。
        """

    private static func argmax(_ values: [Float]) -> Int {
        values.indices.max { values[$0] < values[$1] } ?? -1
    }
}
