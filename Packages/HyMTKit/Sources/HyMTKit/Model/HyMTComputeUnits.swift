//
//  HyMTComputeUnits.swift
//  HyMTKit
//
//  Created by Lorpaves on 2026/11/13.
//

import Foundation
import Metal

/// Where llama.cpp runs the model.
public enum HyMTComputeUnits: Sendable {
    /// GPU when its Metal family has llama.cpp's fast matrix kernels (Apple7: A14 / M1 and later), otherwise CPU
    /// (default). On an iPhone 11 (A13) the GPU path measured 2.6 tok/s against 9.2 tok/s on the CPU.
    /// - Note: Intel Macs also resolve to the CPU; pass ``gpu`` to try their GPU.
    case automatic
    /// Every layer on the GPU through Metal. Operations Metal cannot run fall back to the CPU inside llama.cpp.
    case gpu
    /// CPU only.
    case cpuOnly

    /// Whether this choice runs the model on the GPU of the current device.
    internal var usesGPU: Bool {
        switch self {
        case .automatic: Self.gpuHasFastKernels
        case .gpu: true
        case .cpuOnly: false
        }
    }

    /// llama.cpp enables its simdgroup matrix-multiply kernels only for `MTLGPUFamilyApple7` and later.
    private static let gpuHasFastKernels = MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) ?? false
}
