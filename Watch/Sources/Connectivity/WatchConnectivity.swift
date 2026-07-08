import Foundation
import Observation
import WatchConnectivity

/// Watch side of the link + capture coordinator.
///
/// Runs the mic through the shared VAD, cuts utterances, ships them to the phone
/// in ~0.5s chunks, and shows the streamed reaction that comes back. This is the
/// "thin client" the memo describes — no model on the Watch.
@MainActor
@Observable
final class WatchConnectivity: NSObject {

    // UI state ---------------------------------------------------------------
    private(set) var reaction: String = ""
    private(set) var isReactionFinal = false
    private(set) var isListening = false
    private(set) var isReachable = false
    private(set) var status: String = ""

    private var session: WCSession?
    private let capture = WatchAudioCapture()
    private var vad = VoiceActivityDetector()

    // Current utterance assembly --------------------------------------------
    private var utteranceId = UUID()
    private var sequence = 0
    private var pending: [Float] = []
    private var sampleRate = WatchAudioCapture.sampleRate
    /// ~0.5s at 16 kHz — small enough for `sendMessageData`, big enough to not spam.
    private let chunkSamples = 8_000

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    // MARK: - Listening control

    func toggleListening() { isListening ? stop() : start() }

    private func start() {
        capture.onBuffer = { [weak self] samples, rate in
            Task { @MainActor in self?.consume(samples: samples, rate: rate) }
        }
        do {
            try capture.start()
            isListening = true
            status = ""
        } catch {
            status = "マイク開始に失敗"
        }
    }

    private func stop() {
        capture.stop()
        vad.reset()
        pending.removeAll()
        isListening = false
    }

    // MARK: - Capture → chunks

    private func consume(samples: [Float], rate: Double) {
        sampleRate = rate
        switch vad.process(samples: samples, sampleRate: rate) {
        case .speechStarted:
            beginUtterance()
            pending.append(contentsOf: samples)
        case .ongoing where vad.isSpeaking:
            pending.append(contentsOf: samples)
            if pending.count >= chunkSamples { flush(isFinal: false) }
        case .speechEnded:
            flush(isFinal: true)
        default:
            break
        }
    }

    private func beginUtterance() {
        utteranceId = UUID()
        sequence = 0
        pending.removeAll()
        reaction = ""
        isReactionFinal = false
    }

    private func flush(isFinal: Bool) {
        guard !pending.isEmpty || isFinal else { return }
        let audio = AudioCodec.encode(samples: pending, sampleRate: sampleRate)
        pending.removeAll()
        let message = WireMessage.utteranceChunk(
            id: utteranceId, sequence: sequence, isFinal: isFinal, audio: audio
        )
        sequence += 1
        send(message)
    }

    private func send(_ message: WireMessage) {
        guard let session, let data = try? message.encoded() else { return }
        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                Task { @MainActor in self?.status = "送信に失敗（iPhoneが近くにありません）" }
            }
        } else {
            // Non-reachable fallback per the memo. Best-effort for finished audio.
            session.transferUserInfo(["payload": data])
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchConnectivity: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.isReachable = session.isReachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.ingest(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        Task { @MainActor in self.ingest(data) }
    }

    @MainActor private func ingest(_ data: Data) {
        guard let message = try? WireMessage.decode(data) else { return }
        if case let .reactionUpdate(_, text, isFinal) = message {
            reaction = text
            isReactionFinal = isFinal
        }
    }
}
