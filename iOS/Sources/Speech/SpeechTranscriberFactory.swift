import Foundation

/// Picks the best STT engine available. Prefers WhisperKit when its package is
/// linked (the memo's preferred route), otherwise falls back to Apple's
/// on-device `SFSpeechRecognizer`. Adding the WhisperKit package is treated as
/// intent to use it.
enum SpeechTranscriberFactory {
    static func makeDefault() -> SpeechTranscribing {
        #if canImport(WhisperKit)
        return WhisperKitTranscriber()
        #else
        return SystemSpeechTranscriber()
        #endif
    }
}
