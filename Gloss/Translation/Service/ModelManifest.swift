//
//  ModelManifest.swift
//  Gloss
//
//  Created by Lorpaves on 2026/11/14.
//

import Foundation

/// The translation model Gloss downloads: Tencent's Hy-MT2-1.8B quantized to Q4_K_M, and its tokenizer.
///
/// Every file is pinned to a revision in each source and checked against its SHA-256 digest, so both sources deliver
/// the same bytes.
internal enum ModelManifest {
    /// Folder name of the installed model.
    internal static let directoryName = "HyMT2-1.8B"
    /// The GGUF weights; the other files belong to the tokenizer.
    internal static let weightsFileName = "Hy-MT2-1.8B-Q4_K_M.gguf"

    internal static let files: [ModelFile] = [
        ModelFile(
            name: weightsFileName,
            size: 1_133_080_448,
            sha256: "dc5f44fcf1fa496ee7ad725982c0c8c553a4de00259b53af84c4b89fb0c06699",
            repository: .weights
        ),
        ModelFile(
            name: "tokenizer.json",
            size: 9_527_287,
            sha256: "b475bbef1b0b2fd57dcb865332b546475bd1ede2deb3bb91bafd0c047a8a530a",
            repository: .tokenizer
        ),
        ModelFile(
            name: "tokenizer_config.json",
            size: 165_815,
            sha256: "53bd8581b601a8ee9caefeb988207de50b3fc0b733295bdf5ad68dec4cc0b07c",
            repository: .tokenizer
        ),
        ModelFile(
            name: "special_tokens_map.json",
            size: 488,
            sha256: "bb9f59990034dae326581b9c62471523975417869f78a244b7ae2ce8cbb085eb",
            repository: .tokenizer
        ),
        ModelFile(
            name: "chat_template.jinja",
            size: 654,
            sha256: "b7491ec0e9c869dfce20f2176758099bf248d979dd05530ede99deb21698acee",
            repository: .tokenizer
        ),
        ModelFile(
            name: "config.json",
            size: 1_348,
            sha256: "da40c514cc74a5748a2e591b1b95fca4b7e94de05349abe4ea4164a82641de1a",
            repository: .tokenizer
        ),
        ModelFile(
            name: "generation_config.json",
            size: 221,
            sha256: "0e28667f1cb4c7b880b9223b2d87978f88e79ed7ae037de1021f826c18d4ed6f",
            repository: .tokenizer
        )
    ]

    /// Size of all files together.
    internal static let totalSize: Int64 = files.reduce(0) { $0 + $1.size }

    /// Where the model is installed: `~/Library/Application Support/Gloss/Models/HyMT2-1.8B`.
    internal static var installDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Gloss/Models/\(directoryName)", directoryHint: .isDirectory)
    }

    // MARK: - Sources

    /// Download URL of `file` in `source`.
    internal static func url(of file: ModelFile, in source: ModelSource) -> URL {
        let path = switch (source, file.repository) {
        case (.huggingFace, .weights):
            "https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF/resolve/a0c709d9fac510f2c807aa3af52872340dc37a4a"
        case (.huggingFace, .tokenizer):
            "https://huggingface.co/tencent/Hy-MT2-1.8B/resolve/9a341cd1b679d3efd23b46e847b01745a71ed792"
        case (.modelScope, .weights):
            "https://www.modelscope.cn/models/Tencent-Hunyuan/Hy-MT2-1.8B-GGUF/resolve/ef1d40b8b315575d30d1eb6579996130b8fc0bb2"
        case (.modelScope, .tokenizer):
            "https://www.modelscope.cn/models/Tencent-Hunyuan/Hy-MT2-1.8B/resolve/136293b8886aff2c0dca64e953e26346a1fc2fbd"
        }
        guard let base = URL(string: path) else {
            preconditionFailure("Malformed model URL \(path)")
        }
        return base.appending(path: file.name)
    }

    /// The source to use until the user picks one: ModelScope in mainland China, where Hugging Face can't be reached,
    /// and Hugging Face everywhere else.
    /// - Parameter region: The user's region code, e.g. `Locale.current.region?.identifier`.
    internal static func defaultSource(forRegion region: String?) -> ModelSource {
        region == "CN" ? .modelScope : .huggingFace
    }
}
