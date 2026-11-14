//
//  SettingsStoreTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import Testing
@testable import Gloss

@MainActor
struct SettingsStoreTests {
    // MARK: - Onboarding

    @Test func testOnboardingIsNotCompletedAtFirstLaunch() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(!SettingsStore(defaults: defaults).hasCompletedOnboarding)
    }

    @Test func testCompletedOnboardingPersistsAcrossLaunches() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsStore(defaults: defaults).hasCompletedOnboarding = true

        #expect(SettingsStore(defaults: defaults).hasCompletedOnboarding)
    }

    // MARK: - Model source

    @Test func testModelSourceFollowsTheRegionUntilPicked() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(
            SettingsStore(defaults: defaults).modelSource
                == ModelManifest.defaultSource(forRegion: Locale.current.region?.identifier)
        )
    }

    @Test func testPickedModelSourcePersistsAcrossLaunches() throws {
        let (defaults, suiteName) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        SettingsStore(defaults: defaults).modelSource = .modelScope

        #expect(SettingsStore(defaults: defaults).settings.modelSource == .modelScope)
    }

    // MARK: - Private

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suiteName = "GlossTests-\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: suiteName)), suiteName)
    }
}
