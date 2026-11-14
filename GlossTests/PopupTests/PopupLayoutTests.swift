//
//  PopupLayoutTests.swift
//  GlossTests
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import CoreGraphics
import Testing
@testable import Gloss

struct PopupLayoutTests {
    private let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    private let anchorWithRoomBelow = CGRect(x: 400, y: 600, width: 120, height: 18)
    private let anchorNearBottom = CGRect(x: 400, y: 60, width: 120, height: 18)
    private let content = CGSize(width: 200, height: 100)

    @Test func testPopupSitsBelowTheSelectionWhenThereIsRoom() {
        let layout = PopupLayout.make(anchor: anchorWithRoomBelow, leadingX: 386, visibleFrame: screen)
        #expect(layout.placement == .below)
        #expect(layout.frame(for: content).maxY == anchorWithRoomBelow.minY - PopupLayout.gap)
    }

    @Test func testPopupTakesTheContentSizeFromItsLeadingEdge() {
        let frame = PopupLayout.make(anchor: anchorWithRoomBelow, leadingX: 386, visibleFrame: screen).frame(for: content)
        #expect(frame.minX == 386)
        #expect(frame.size == content)
    }

    @Test func testWidthIsCappedAtTheMaximum() {
        let frame = PopupLayout.make(anchor: anchorWithRoomBelow, leadingX: 386, visibleFrame: screen)
            .frame(for: CGSize(width: 900, height: 100))
        #expect(frame.width == PopupLayout.maximumWidth)
    }

    @Test func testPopupFlipsAboveNearTheBottomOfTheScreen() {
        let layout = PopupLayout.make(anchor: anchorNearBottom, leadingX: 386, visibleFrame: screen)
        #expect(layout.placement == .above)
        #expect(layout.frame(for: content).minY == anchorNearBottom.maxY + PopupLayout.gap)
    }

    @Test func testPopupStaysInsideTheScreenEdges() {
        let right = PopupLayout.make(anchor: anchorWithRoomBelow, leadingX: 1400, visibleFrame: screen)
        let left = PopupLayout.make(anchor: anchorWithRoomBelow, leadingX: -12, visibleFrame: screen)
        #expect(right.frame(for: content).maxX == screen.maxX - PopupLayout.margin)
        #expect(left.frame(for: content).minX == screen.minX + PopupLayout.margin)
    }

    @Test func testGrowingKeepsTheLeadingAndAnchoredEdges() {
        let below = PopupLayout.make(anchor: anchorWithRoomBelow, leadingX: 386, visibleFrame: screen)
        let small = below.frame(for: CGSize(width: 80, height: 40))
        let large = below.frame(for: CGSize(width: 380, height: 300))
        #expect(small.minX == large.minX)
        #expect(small.maxY == large.maxY)
    }

    @Test func testGrowingAboveKeepsTheBottomEdge() {
        let above = PopupLayout.make(anchor: anchorNearBottom, leadingX: 386, visibleFrame: screen)
        #expect(above.frame(for: CGSize(width: 80, height: 40)).minY == above.frame(for: CGSize(width: 380, height: 300)).minY)
    }

    @Test func testHeightIsCappedByTheRoomBelow() {
        let layout = PopupLayout.make(anchor: CGRect(x: 400, y: 250, width: 120, height: 18), leadingX: 386, visibleFrame: screen)
        #expect(layout.placement == .below)
        #expect(layout.maxHeight == 236)
        #expect(layout.frame(for: CGSize(width: 200, height: 1000)).height == 236)
    }

    @Test func testHeightIsCappedAtTheMaximumWithPlentyOfRoom() {
        let layout = PopupLayout.make(anchor: CGRect(x: 400, y: 800, width: 120, height: 18), leadingX: 386, visibleFrame: screen)
        #expect(layout.maxHeight == PopupLayout.maximumHeight)
    }

    @Test func testDraggingReanchorsThePopup() {
        var layout = PopupLayout.make(anchor: anchorWithRoomBelow, leadingX: 386, visibleFrame: screen)
        layout.move(to: CGRect(x: 100, y: 300, width: 200, height: 80))
        let frame = layout.frame(for: CGSize(width: 250, height: 120))
        #expect(frame.minX == 100)
        #expect(frame.maxY == 380)
    }
}
