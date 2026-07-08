import Foundation

/// Picks the best reaction engine available on this device.
///
/// Preference order:
///   1. **MLX / Qwen** when its package is linked — the memo's "自由度ルート"
///      for stronger Japanese and character. Linking the package = intent to use it.
///   2. **Foundation Models** (iOS 26+, Apple Intelligence) — fastest first token.
///   3. **Echo** — always works, no model, keeps the pipeline exercisable.
enum ReactionEngineFactory {
    static func makeDefault() -> ReactionGenerating {
        #if canImport(MLXLLM)
        return MLXReactionEngine()
        #else
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let fm = FoundationModelsEngine()
            if fm.isAvailable { return fm }
        }
        #endif
        return EchoReactionEngine()
        #endif
    }
}
