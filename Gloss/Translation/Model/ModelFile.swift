//
//  ModelFile.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// One file of the translation model.
internal struct ModelFile: Equatable, Sendable {
    /// File name, the same in every source and on disk.
    internal var name: String
    /// Size in bytes.
    internal var size: Int64
    /// SHA-256 digest of the contents, in lowercase hex.
    internal var sha256: String
    /// Which of the model's repositories holds the file.
    internal var repository: ModelRepository
}
