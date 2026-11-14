//
//  PopupHostingView.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import AppKit
import SwiftUI

/// Hosts the popup content. Accepts the first click, so its buttons work although the panel never becomes key.
internal final class PopupHostingView<Content: View>: NSHostingView<Content> {
    override internal func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }
}
