//
//  ModelManifestTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import Testing
@testable import Gloss

struct ModelManifestTests {
    // MARK: - Files

    @Test func testTotalSizeIsTheSumOfTheFiles() {
        #expect(ModelManifest.totalSize == ModelManifest.files.reduce(0) { $0 + $1.size })
    }

    @Test func testWeightsAreAmongTheFiles() {
        #expect(ModelManifest.files.contains { $0.name == ModelManifest.weightsFileName && $0.repository == .weights })
    }

    @Test func testEveryDigestIsLowercaseHexSHA256() {
        let hex = Set("0123456789abcdef")
        #expect(ModelManifest.files.allSatisfy { $0.sha256.count == 64 && $0.sha256.allSatisfy(hex.contains) })
    }

    @Test func testModelIsInstalledInApplicationSupport() {
        #expect(ModelManifest.installDirectory.path.hasSuffix("Application Support/Gloss/Models/HyMT2-1.8B"))
    }

    // MARK: - Sources

    @Test func testHuggingFaceURLIsPinnedToARevision() throws {
        let weights = try #require(ModelManifest.files.first { $0.repository == .weights })
        #expect(
            ModelManifest.url(of: weights, in: .huggingFace).absoluteString
                == "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/a0c709d9fac510f2c807aa3af52872340dc37a4a/Hy-MT2-1.8B-Q4_K_M.gguf"
        )
    }

    @Test func testModelScopeURLIsPinnedToARevision() throws {
        let tokenizer = try #require(ModelManifest.files.first { $0.name == "tokenizer.json" })
        #expect(
            ModelManifest.url(of: tokenizer, in: .modelScope).absoluteString
                == "https://www.modelscope.cn/models/Tencent-Hunyuan/Hy-MT2-1.8B/resolve/136293b8886aff2c0dca64e953e26346a1fc2fbd/tokenizer.json"
        )
    }

    @Test func testMainlandChinaDefaultsToModelScope() {
        #expect(ModelManifest.defaultSource(forRegion: "CN") == .modelScope)
    }

    @Test func testOtherRegionsDefaultToHuggingFace() {
        #expect(ModelManifest.defaultSource(forRegion: "US") == .huggingFace)
        #expect(ModelManifest.defaultSource(forRegion: "HK") == .huggingFace)
        #expect(ModelManifest.defaultSource(forRegion: nil) == .huggingFace)
    }
}
