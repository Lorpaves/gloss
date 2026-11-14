//
//  ModelDownloadFailure.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// Why a model download stopped, in terms the user can act on.
internal enum ModelDownloadFailure: Equatable, Sendable {
    /// The download source couldn't be reached.
    case offline
    /// The disk doesn't have room for the rest of the model.
    case notEnoughSpace
    /// A downloaded file didn't match its digest.
    case corrupted
    /// The download source answered with an error.
    case server
    case other
}
