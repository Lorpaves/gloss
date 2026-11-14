//
//  ScreenGeometryTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics
import Testing
@testable import Gloss

struct ScreenGeometryTests {
    private let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]

    @Test func testFlippingConvertsBetweenQuartzAndCocoaBothWays() {
        let quartz = CGRect(x: 100, y: 50, width: 200, height: 20)
        let cocoa = ScreenGeometry.flipped(quartz, primaryScreenHeight: 1000)
        #expect(cocoa == CGRect(x: 100, y: 930, width: 200, height: 20))
        #expect(ScreenGeometry.flipped(cocoa, primaryScreenHeight: 1000) == quartz)
    }

    @Test func testFlippingHandlesDisplaysAboveAndLeftOfThePrimary() {
        let cocoa = ScreenGeometry.flipped(CGPoint(x: -300, y: -200), primaryScreenHeight: 1000)
        #expect(cocoa == CGPoint(x: -300, y: 1200))
    }

    @Test func testSelectionRectAnchorsThePopup() {
        #expect(ScreenGeometry.isUsableAnchor(CGRect(x: 100, y: 100, width: 80, height: 18), screenFrames: screens))
    }

    @Test(arguments: [
        CGRect(x: 100, y: 100, width: 0, height: 18),
        CGRect(x: 5000, y: 100, width: 80, height: 18),
        CGRect(x: 100, y: 50, width: 600, height: 700),
        CGRect(x: CGFloat.nan, y: 0, width: 10, height: 10)
    ])
    func testUnusableRectsFallBackToThePointer(rect: CGRect) {
        #expect(!ScreenGeometry.isUsableAnchor(rect, screenFrames: screens))
    }

    @Test func testPointWithinDistanceIsNearTheRect() {
        let rect = CGRect(x: 100, y: 100, width: 80, height: 18)
        #expect(ScreenGeometry.isPoint(CGPoint(x: 90, y: 110), near: rect, within: 40))
        #expect(!ScreenGeometry.isPoint(CGPoint(x: 400, y: 400), near: rect, within: 40))
    }

    @Test func testPressAnchorSpansTheDragFromStartToEnd() {
        let anchor = ScreenGeometry.pressAnchor(from: CGPoint(x: 300, y: 500), to: CGPoint(x: 120, y: 460))
        #expect(anchor.minX == 120 && anchor.maxX == 301)
        #expect(anchor.minY == 450 && anchor.maxY == 510)
    }

    @Test func testScreenWithThePointOrTheNearestOneIsChosen() {
        let main = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let left = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        #expect(ScreenGeometry.frame(containing: CGPoint(x: -100, y: 500), in: [main, left]) == left)
        #expect(ScreenGeometry.frame(containing: CGPoint(x: 1500, y: 500), in: [main, left]) == main)
    }

    // MARK: - Visible part

    @Test func testSelectionInsideItsScrollAreaIsVisibleAsIs() {
        let selection = CGRect(x: 120, y: 400, width: 200, height: 60)
        let scrollArea = CGRect(x: 100, y: 100, width: 260, height: 800)
        #expect(ScreenGeometry.visiblePart(of: selection, clippedBy: [scrollArea]) == selection)
    }

    @Test func testSelectionCutByItsScrollAreaKeepsThePartInView() {
        let selection = CGRect(x: 120, y: 860, width: 200, height: 60)
        let scrollArea = CGRect(x: 100, y: 100, width: 260, height: 800)
        #expect(
            ScreenGeometry.visiblePart(of: selection, clippedBy: [scrollArea])
                == CGRect(x: 120, y: 860, width: 200, height: 40)
        )
    }

    @Test func testSelectionScrolledOutOfItsScrollAreaHasNoVisiblePart() {
        let selection = CGRect(x: 120, y: 950, width: 200, height: 60)
        let scrollArea = CGRect(x: 100, y: 100, width: 260, height: 800)
        #expect(ScreenGeometry.visiblePart(of: selection, clippedBy: [scrollArea]) == nil)
    }

    @Test func testSelectionTouchingTheEdgeOfItsScrollAreaHasNoVisiblePart() {
        let selection = CGRect(x: 120, y: 900, width: 200, height: 60)
        let scrollArea = CGRect(x: 100, y: 100, width: 260, height: 800)
        #expect(ScreenGeometry.visiblePart(of: selection, clippedBy: [scrollArea]) == nil)
    }

    /// Xcode's Quick Help: the web view's own scroll area is as tall as the page and moves with the text; the
    /// inspector's scroll area around it is what clips.
    @Test func testOuterScrollAreaClipsWhenTheInnerOneMovesWithTheText() {
        let selection = CGRect(x: 2166, y: 1300, width: 228, height: 96)
        let pageScrollArea = CGRect(x: 2150, y: -1200, width: 260, height: 3000)
        let inspectorScrollArea = CGRect(x: 2150, y: 166, width: 260, height: 820)
        #expect(ScreenGeometry.visiblePart(of: selection, clippedBy: [pageScrollArea, inspectorScrollArea]) == nil)
    }

    @Test func testSelectionWithoutKnownClipFramesIsVisibleAsIs() {
        let selection = CGRect(x: 120, y: 400, width: 200, height: 60)
        #expect(ScreenGeometry.visiblePart(of: selection, clippedBy: []) == selection)
    }

    // MARK: - Screen showing a rect

    @Test func testScreenShowingMostOfTheRectIsChosen() {
        let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let right = CGRect(x: 2560, y: -1032, width: 1440, height: 2560)
        let mostlyOnMain = CGRect(x: 2400, y: 700, width: 200, height: 20)
        let mostlyOnRight = CGRect(x: 2500, y: 700, width: 200, height: 20)
        #expect(ScreenGeometry.frame(showingMostOf: mostlyOnMain, in: [main, right]) == main)
        #expect(ScreenGeometry.frame(showingMostOf: mostlyOnRight, in: [main, right]) == right)
    }

    /// A selection scrolled past the top of its screen belongs to no screen, even with a taller display next to it.
    @Test func testRectOffEveryScreenHasNoScreen() {
        let main = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let right = CGRect(x: 2560, y: -1032, width: 1440, height: 2560)
        let aboveMain = CGRect(x: 2166, y: 1800, width: 228, height: 96)
        #expect(ScreenGeometry.frame(showingMostOf: aboveMain, in: [main, right]) == nil)
    }
}
