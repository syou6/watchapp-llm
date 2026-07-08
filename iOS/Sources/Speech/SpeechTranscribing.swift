import Foundation

/// The STT seam. The pipeline talks to this; concrete engines
/// (`SystemSpeechTranscriber` now, a WhisperKit-backed one later) plug in behind
/// it. Keeping this a protocol is the whole point of build-order step 3 in the
/// design memo: swap the transcriber without touching the pipeline.
protocol SpeechTranscribing: AnyObject {
    /// Transcribe one finished utterance's worth of 16 kHz mono samples.
    /// Returns the recognized text (may be empty for non-speech).
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String
}

enum SpeechError: Error, LocalizedError {
    case unauthorized
    case unavailable
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:      return "音声認識の許可がありません（設定 > プライバシー）"
        case .unavailable:       return "この端末では音声認識を利用できません"
        case .recognitionFailed(let m): return "認識に失敗しました: \(m)"
        }
    }
}
