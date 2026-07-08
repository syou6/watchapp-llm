import Foundation

/// Picks the best reaction engine available on this device.
///
/// Order matches the design memo's ramp: Foundation Models first (fastest to
/// stand up), Echo as the always-works fallback. When you add an MLX engine,
/// insert it here — e.g. prefer Foundation Models for latency, fall back to MLX
/// for quality/older devices, per your taste.
enum ReactionEngineFactory {
    static func makeDefault() -> ReactionGenerating {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let fm = FoundationModelsEngine()
            if fm.isAvailable { return fm }
        }
        #endif
        // TODO: try MLXReactionEngine() here once mlx-swift is wired in.
        return EchoReactionEngine()
    }
}
