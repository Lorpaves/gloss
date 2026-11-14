//
//  ModelState.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation

/// Where the translation model stands: downloaded or not, loaded or not.
internal enum ModelState: Equatable, Sendable {
    /// The model isn't on this Mac. A stopped download keeps what it got and continues from there.
    case notDownloaded
    /// `received` of `total` bytes are on disk.
    case downloading(received: Int64, total: Int64)
    /// Checking the downloaded weights against their digest.
    case verifying
    case downloadFailed(ModelDownloadFailure)
    case loading
    case ready
    case loadFailed
}
