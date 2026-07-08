import AVFoundation
import Foundation
import Speech

/// On-device STT via Apple's `SFSpeechRecognizer` — the "lighter" route the
/// design memo lists as an alternative to WhisperKit. Zero dependencies and
/// good enough for MVP Japanese; forced on-device so nothing leaves the phone.
final class SystemSpeechTranscriber: SpeechTranscribing {

    private let recognizer: SFSpeechRecognizer?

    init(locale: Locale = Locale(identifier: "ja-JP")) {
        self.recognizer = SFSpeechRecognizer(locale: locale)
    }

    /// Ask for permission up front (call once at app start).
    static func requestAuthorization() async -> Bool {
        await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
    }

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        guard let recognizer, recognizer.isAvailable else { throw SpeechError.unavailable }
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            throw SpeechError.unauthorized
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.requiresOnDeviceRecognition = true
        request.shouldReportPartialResults = false

        guard let buffer = Self.makeBuffer(samples: samples, sampleRate: sampleRate) else {
            throw SpeechError.recognitionFailed("バッファ生成に失敗")
        }
        request.append(buffer)
        request.endAudio()

        return try await withCheckedThrowingContinuation { cont in
            var didResume = false
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    guard !didResume else { return }
                    didResume = true
                    cont.resume(throwing: SpeechError.recognitionFailed(error.localizedDescription))
                    return
                }
                if let result, result.isFinal {
                    guard !didResume else { return }
                    didResume = true
                    cont.resume(returning: result.bestTranscription.formattedString)
                }
            }
            _ = task
        }
    }

    private static func makeBuffer(samples: [Float], sampleRate: Double) -> AVAudioPCMBuffer? {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ), let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(samples.count)
        ) else { return nil }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        if let channel = buffer.floatChannelData {
            samples.withUnsafeBufferPointer { src in
                channel[0].update(from: src.baseAddress!, count: samples.count)
            }
        }
        return buffer
    }
}
