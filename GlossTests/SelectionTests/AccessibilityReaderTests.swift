//
//  AccessibilityReaderTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Testing
@testable import Gloss

struct AccessibilityReaderTests {
    // MARK: - Chromium browsers

    @Test func testChromiumBrowserIsRecognized() throws {
        let bundle = try makeAppBundle(framework: "Google Chrome Framework.framework", urlSchemes: ["http", "https"])
        defer { removeAppBundle(bundle) }
        #expect(AccessibilityReader.isChromiumBrowser(bundleURL: bundle))
    }

    @Test func testElectronAppIsNotTreatedAsABrowser() throws {
        let bundle = try makeAppBundle(framework: "Electron Framework.framework", urlSchemes: ["slack"])
        defer { removeAppBundle(bundle) }
        #expect(!AccessibilityReader.isChromiumBrowser(bundleURL: bundle))
    }

    @Test func testBrowserWithoutChromiumIsNotTreatedAsChromium() throws {
        let bundle = try makeAppBundle(framework: nil, urlSchemes: ["http", "https"])
        defer { removeAppBundle(bundle) }
        #expect(!AccessibilityReader.isChromiumBrowser(bundleURL: bundle))
    }

    @Test func testMissingBundleIsNotABrowser() {
        #expect(!AccessibilityReader.isChromiumBrowser(bundleURL: nil))
    }

    // MARK: - Private

    /// Builds a minimal app bundle in its own temporary folder.
    private func makeAppBundle(framework: String?, urlSchemes: [String]) throws -> URL {
        let bundle = FileManager.default.temporaryDirectory.appending(path: "test_\(UUID().uuidString)/Test.app")
        let contents = bundle.appending(path: "Contents")
        try FileManager.default.createDirectory(
            at: contents.appending(path: "Frameworks/\(framework ?? "")"),
            withIntermediateDirectories: true
        )
        let info: [String: Any] = [
            "CFBundleIdentifier": "com.example.test-\(UUID().uuidString)",
            "CFBundleURLTypes": [["CFBundleURLSchemes": urlSchemes]]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try data.write(to: contents.appending(path: "Info.plist"))
        return bundle
    }

    private func removeAppBundle(_ bundle: URL) {
        try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent())
    }
}
