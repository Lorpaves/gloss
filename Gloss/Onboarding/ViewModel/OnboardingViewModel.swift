//
//  OnboardingViewModel.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import Observation

/// The welcome guide shown at first launch: its pages, the one showing, and what their buttons do.
@MainActor
@Observable
internal final class OnboardingViewModel {
    // MARK: - Properties

    internal private(set) var step: OnboardingStep = .welcome
    /// The pages in order. Those already taken care of (a permission granted earlier) are left out.
    internal let steps: [OnboardingStep]

    internal let accessibility: AccessibilityPermission
    internal let clipboard: ClipboardPermission
    internal let model: ModelManager
    internal let settingsStore: SettingsStore

    /// Closes the guide.
    @ObservationIgnored internal var onFinish: () -> Void = {}
    /// Brings the guide back in front of System Settings once the user granted a permission there.
    @ObservationIgnored internal var onPermissionGranted: () -> Void = {}

    // MARK: - Lifecycle

    internal init(
        accessibility: AccessibilityPermission,
        clipboard: ClipboardPermission,
        model: ModelManager,
        settingsStore: SettingsStore
    ) {
        self.accessibility = accessibility
        self.clipboard = clipboard
        self.model = model
        self.settingsStore = settingsStore
        steps = Self.steps(
            needsAccessibility: !accessibility.isTrusted,
            needsClipboard: settingsStore.settings.usesCopyFallback && !clipboard.isAllowed,
            needsModel: !model.isInstalled
        )
    }

    // MARK: - Queries

    internal var stepIndex: Int {
        steps.firstIndex(of: step) ?? 0
    }

    internal var canGoBack: Bool {
        stepIndex > 0
    }

    /// The pages for what still needs setting up, between the welcome and the last page.
    internal static func steps(needsAccessibility: Bool, needsClipboard: Bool, needsModel: Bool) -> [OnboardingStep] {
        var steps: [OnboardingStep] = [.welcome]
        if needsAccessibility {
            steps.append(.accessibility)
        }
        if needsClipboard {
            steps.append(.clipboard)
        }
        if needsModel {
            steps.append(.model)
        }
        steps.append(.finish)
        return steps
    }

    // MARK: - Navigation

    /// Shows the next page. After the last one, records the guide as done, so it no longer opens at launch, and
    /// closes it; closing the window before that leaves the guide to open again.
    internal func next() {
        guard stepIndex + 1 < steps.count else {
            settingsStore.hasCompletedOnboarding = true
            onFinish()
            return
        }
        step = steps[stepIndex + 1]
    }

    internal func back() {
        guard canGoBack else { return }
        step = steps[stepIndex - 1]
    }

    /// Records the page the user swiped to.
    internal func show(_ step: OnboardingStep) {
        guard steps.contains(step) else { return }
        self.step = step
    }

    // MARK: - Actions

    internal func requestAccessibility() {
        accessibility.requestAccess()
    }

    internal func requestClipboardAccess() {
        clipboard.request()
    }

    internal func downloadModel() {
        model.download(from: settingsStore.modelSource)
    }

    internal func cancelDownload() {
        model.cancelDownload()
    }

    internal func retryModelLoad() {
        model.retryLoad()
    }

    /// Called when a permission the current page asks for turns on.
    internal func permissionWasGranted() {
        onPermissionGranted()
    }
}
