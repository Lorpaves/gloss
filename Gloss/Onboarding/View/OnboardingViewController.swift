//
//  OnboardingViewController.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation
import AppKit
import SwiftUI
import Observation

/// The welcome guide's content: its pages in an `NSPageController` that slides them as one strip, and a footer
/// below that stays put.
///
/// The view model's ``OnboardingViewModel/step`` decides the page; swiping the pages with the trackpad changes it.
@MainActor
internal final class OnboardingViewController: NSViewController, NSPageControllerDelegate {
    // MARK: - Views

    private let pageController = NSPageController()
    private lazy var footer: NSHostingView<OnboardingFooterView> = {
        let footer = NSHostingView(rootView: OnboardingFooterView(viewModel: viewModel))
        // Sized by this controller; SwiftUI mustn't push back with constraints of its own.
        footer.sizingOptions = []
        return footer
    }()

    // MARK: - Props

    private let viewModel: OnboardingViewModel
    /// A slide is running; a page change that comes in meanwhile follows once it's done.
    private var isSliding = false

    /// Size of the guide below the title bar.
    internal static let contentSize = NSSize(width: 540, height: 440)
    private static let footerHeight: CGFloat = 64
    private static let slideDuration: TimeInterval = 0.3

    // MARK: - Lifecycle

    internal init(viewModel: OnboardingViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override internal func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: Self.contentSize))
    }

    override internal func viewDidLoad() {
        super.viewDidLoad()
        commonInit()
    }

    override internal func viewDidLayout() {
        super.viewDidLayout()
        // AppKit's y axis points up: the footer takes the bottom strip, the pages the rest.
        let bounds = view.bounds
        footer.frame = NSRect(x: 0, y: 0, width: bounds.width, height: Self.footerHeight)
        pageController.view.frame = NSRect(
            x: 0,
            y: Self.footerHeight,
            width: bounds.width,
            height: max(bounds.height - Self.footerHeight, 0)
        )
    }

    // MARK: - NSPageControllerDelegate

    internal func pageController(
        _ pageController: NSPageController,
        identifierFor object: Any
    ) -> NSPageController.ObjectIdentifier {
        (object as? OnboardingStep).map(Self.identifier(of:)) ?? ""
    }

    internal func pageController(
        _ pageController: NSPageController,
        viewControllerForIdentifier identifier: NSPageController.ObjectIdentifier
    ) -> NSViewController {
        let step = viewModel.steps.first { Self.identifier(of: $0) == identifier } ?? .welcome
        let page = NSHostingController(rootView: OnboardingPageView(step: step, viewModel: viewModel))
        // The page controller sizes the pages; SwiftUI mustn't push back with constraints of its own.
        page.sizingOptions = []
        page.view.frame = pageController.view.bounds
        page.view.autoresizingMask = [.width, .height]
        return page
    }

    internal func pageController(_ pageController: NSPageController, frameFor object: Any?) -> NSRect {
        // Without this the pages slide at zero size, their content bunched in a corner until the slide ends.
        pageController.view.bounds
    }

    internal func pageController(
        _ pageController: NSPageController,
        prepare viewController: NSViewController,
        with object: Any?
    ) {
        // Laid out before the slide, so the page doesn't come in empty.
        viewController.view.layoutSubtreeIfNeeded()
    }

    internal func pageController(_ pageController: NSPageController, didTransitionTo object: Any) {
        // Reached by swiping, or at the end of a slide the view model asked for.
        if let step = object as? OnboardingStep {
            viewModel.show(step)
        }
    }

    internal func pageControllerDidEndLiveTransition(_ pageController: NSPageController) {
        pageController.completeTransition()
    }

    // MARK: - Private

    private func commonInit() {
        addSubviews()
        configure()
        followStep()
    }

    private func addSubviews() {
        pageController.view = NSView()
        addChild(pageController)
        view.addSubview(pageController.view)
        view.addSubview(footer)
    }

    private func configure() {
        pageController.delegate = self
        pageController.transitionStyle = .horizontalStrip
        pageController.arrangedObjects = viewModel.steps
        pageController.selectedIndex = viewModel.stepIndex
    }

    /// Slides to the view model's page whenever it changes.
    private func followStep() {
        withObservationTracking {
            _ = viewModel.step
        } onChange: { [weak self] in
            // Called before the change; act on it once it's made.
            Task { @MainActor [weak self] in
                self?.slideToCurrentStep()
                self?.followStep()
            }
        }
    }

    private func slideToCurrentStep() {
        guard !isSliding else { return }
        let index = viewModel.stepIndex
        guard index != pageController.selectedIndex else { return }
        isSliding = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.slideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pageController.animator().selectedIndex = index
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.pageController.completeTransition()
                self.isSliding = false
                // The page may have changed again during the slide.
                self.slideToCurrentStep()
            }
        }
    }

    private static func identifier(of step: OnboardingStep) -> NSPageController.ObjectIdentifier {
        String(describing: step)
    }
}
