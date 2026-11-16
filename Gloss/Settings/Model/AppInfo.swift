//
//  AppInfo.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/16.
//

import Foundation

/// What the About tab says about the running app.
internal struct AppInfo: Equatable, Sendable {
    // MARK: - Properties

    /// The version users see, e.g. "1.0.2".
    internal var version: String
    /// The build number, e.g. "3".
    internal var build: String
    /// The copyright line of the app's Info.plist.
    internal var copyright: String

    internal static let website = "https://gloss.lorpaves.com"
    internal static let repository = "https://github.com/lorpaves/gloss"
    internal static let issues = "https://github.com/lorpaves/gloss/issues"
    /// The license Gloss itself is distributed under.
    internal static let license = "GPL-3.0"

    // MARK: - Lifecycle

    internal init(version: String, build: String, copyright: String) {
        self.version = version
        self.build = build
        self.copyright = copyright
    }

    /// Reads the app's own Info.plist.
    internal init(bundle: Bundle = .main) {
        let info = bundle.infoDictionary ?? [:]
        self.init(
            version: info["CFBundleShortVersionString"] as? String ?? "",
            build: info["CFBundleVersion"] as? String ?? "",
            copyright: info["NSHumanReadableCopyright"] as? String ?? ""
        )
    }

    // MARK: - Queries

    /// The licenses of the software shipped inside the app, as bundled with it.
    internal static func thirdPartyNotices(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "ThirdPartyNotices", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }
}
