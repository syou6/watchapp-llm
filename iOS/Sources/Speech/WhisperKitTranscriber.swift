import Foundation

#if canImport(WhisperKit)
import WhisperKit

/// On-device STT via WhisperKit (the design memo's preferred route: streaming
/// Whisper, strong Japanese). Drop-in behind `SpeechTranscribing`, so the
/// pipeline is unaware of the swap.
///
/// WhisperKit wants 16 kHz mono `Float` — exactly what our capture graph emits,
/// so samples pass straight through with no resampling.
final class WhisperKitTranscriber: SpeechTranscribing {

    private let loader: WhisperLoader
    private let language: String

    /// - Parameters:
    ///   - model: WhisperKit model variant to load (downloaded/cached on first use).
    ///     `"base"` is a good latency/quality balance for short utterances;
    ///     bump to `"large-v3"` for accuracy.
    ///   - language: ISO code passed to the decoder. `"ja"` for Japanese.
    init(model: String = "base", language: String = "ja") {
        self.loader = WhisperLoader(model: model)
        self.language = language
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        let pipe = try await loader.pipe()
        let options = DecodingOptions(task: .transcribe, language: language)
        let results = try await pipe.transcribe(audioArray: samples, decodeOptions: options)
        return results
            .map(\.text)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Serializes model load so the (expensive) `WhisperKit` init happens once,
/// even under concurrent first calls.
private actor WhisperLoader {
    private let model: String
    private var pipeline: WhisperKit?

    init(model: String) { self.model = model }

    func pipe() async throws -> WhisperKit {
        if let pipeline { return pipeline }
        let created = try await WhisperKit(WhisperKitConfig(model: model))
        pipeline = created
        return created
    }
}
#endif
