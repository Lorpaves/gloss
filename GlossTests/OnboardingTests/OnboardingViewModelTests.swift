//
//  OnboardingViewModelTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import AppKit
import Testing
@testable import Gloss

@MainActor
struct OnboardingViewModelTests {
    // MARK: - Pages

    @Test func testEverythingToSetUpGetsAPageInOrder() {
        let steps = OnboardingViewModel.steps(needsAccessibility: true, needsClipboard: true, needsModel: true)
        #expect(steps == [.welcome, .accessibility, .clipboard, .model, .finish])
    }

    @Test func testPagesForWhatIsDoneAreLeftOut() {
        let steps = OnboardingViewModel.steps(needsAccessibility: false, needsClipboard: false, needsModel: true)
        #expect(steps == [.welcome, .model, .finish])
    }

    @Test func testNothingToSetUpLeavesWelcomeAndFinish() {
        let steps = OnboardingViewModel.steps(needsAccessibility: false, needsClipboard: false, needsModel: false)
        #expect(steps == [.welcome, .finish])
    }

    // MARK: - Navigation

    @Test func testGuideStartsAtWelcome() throws {
        let (viewModel, cleanUp) = try makeViewModel()
        defer { cleanUp() }

        #expect(viewModel.step == .welcome)
        #expect(!viewModel.canGoBack)
    }

    @Test func testNextShowsTheFollowingPage() throws {
        let (viewModel, cleanUp) = try makeViewModel()
        defer { cleanUp() }

        viewModel.next()

        #expect(viewModel.step == viewModel.steps[1])
    }

    @Test func testBackShowsThePreviousPage() throws {
        let (viewModel, cleanUp) = try makeViewModel()
        defer { cleanUp() }

        viewModel.next()
        viewModel.back()

        #expect(viewModel.step == .welcome)
    }

    @Test func testNextOnTheLastPageFinishes() throws {
        let (viewModel, cleanUp) = try makeViewModel()
        defer { cleanUp() }
        var finished = false
        viewModel.onFinish = { finished = true }

        for _ in viewModel.steps {
            viewModel.next()
        }

        #expect(viewModel.step == .finish)
        #expect(finished)
    }

    @Test func testSwipingToAPageMakesItCurrent() throws {
        let (viewModel, cleanUp) = try makeViewModel()
        defer { cleanUp() }

        viewModel.show(.finish)

        #expect(viewModel.step == .finish)
    }

    @Test func testSwipingToAPageTheGuideLeftOutIsIgnored() throws {
        // Without the copy fallback the guide has no clipboard page.
        let (viewModel, cleanUp) = try makeViewModel(usesCopyFallback: false)
        defer { cleanUp() }

        viewModel.show(.clipboard)

        #expect(viewModel.step == .welcome)
    }

    @Test func testFinishingTheGuideMarksItDone() throws {
        let (viewModel, cleanUp) = try makeViewModel()
        defer { cleanUp() }

        for _ in viewModel.steps {
            viewModel.next()
        }

        #expect(viewModel.settingsStore.hasCompletedOnboarding)
    }

    @Test func testLeavingBeforeTheLastPageDoesNotMarkTheGuideDone() throws {
        let (viewModel, cleanUp) = try makeViewModel()
        defer { cleanUp() }

        for _ in viewModel.steps.dropLast() {
            viewModel.next()
        }

        #expect(viewModel.step == .finish)
        #expect(!viewModel.settingsStore.hasCompletedOnboarding)
    }

    // MARK: - Private

    /// A guide over a model folder that doesn't exist, so it always has the model page.
    private func makeViewModel(usesCopyFallback: Bool = true) throws -> (OnboardingViewModel, () -> Void) {
        let suiteName = "GlossTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        let settingsStore = SettingsStore(defaults: defaults)
        settingsStore.settings.usesCopyFallback = usesCopyFallback
        let directory = FileManager.default.temporaryDirectory.appending(path: "OnboardingTests-\(UUID().uuidString)")
        let engine = TranslationEngine(modelDirectory: directory)
        let viewModel = OnboardingViewModel(
            accessibility: AccessibilityPermission(),
            clipboard: ClipboardPermission(pasteboard: NSPasteboard(name: NSPasteboard.Name("GlossTests-\(UUID().uuidString)"))),
            model: ModelManager(directory: directory, engine: engine, downloader: ModelDownloader()),
            settingsStore: settingsStore
        )
        return (viewModel, { defaults.removePersistentDomain(forName: suiteName) })
    }
}
