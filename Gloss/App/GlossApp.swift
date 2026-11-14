//
//  GlossApp.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import SwiftUI

/// Menu bar app (no Dock icon) that translates text selected in other apps.
@main
internal struct GlossApp: App {
    // MARK: - Properties

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // MARK: - Body

    internal var body: some Scene {
        MenuBarExtra {
            MenuBarContentView(coordinator: appDelegate.coordinator)
        } label: {
            if appDelegate.coordinator.needsAttention {
                Image(systemName: "exclamationmark.triangle")
            } else {
                Image(nsImage: MenuBarIcon.image)
                    .renderingMode(.template)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}
