import Foundation

/// Dead-simple energy-gate VAD.
///
/// Speech onset = RMS crosses `threshold`; end-of-utterance = RMS stays below
/// it for `hangoverSeconds`. That's enough to cut utterances the way the design
/// memo describes ("speaker pauses ~0.3s"). Swap for WhisperKit's built-in VAD
/// or a Silero model if you need robustness in noise.
struct VoiceActivityDetector {

    var threshold: Float = 0.015
    var hangoverSeconds: Double = 0.35

    private(set) var isSpeaking = false
    private var silenceDuration: Double = 0

    enum Event: Equatable {
        case speechStarted
        case speechEnded
        case ongoing
    }

    /// Feed one buffer's worth of samples. Returns a transition event, if any.
    mutating func process(samples: [Float], sampleRate: Double) -> Event {
        guard !samples.isEmpty else { return .ongoing }

        var sumSquares: Float = 0
        for s in samples { sumSquares += s * s }
        let rms = (sumSquares / Float(samples.count)).squareRoot()
        let duration = Double(samples.count) / sampleRate

        if rms >= threshold {
            silenceDuration = 0
            if !isSpeaking {
                isSpeaking = true
                return .speechStarted
            }
            return .ongoing
        } else {
            guard isSpeaking else { return .ongoing }
            silenceDuration += duration
            if silenceDuration >= hangoverSeconds {
                isSpeaking = false
                silenceDuration = 0
                return .speechEnded
            }
            return .ongoing
        }
    }

    mutating func reset() {
        isSpeaking = false
        silenceDuration = 0
    }
}
