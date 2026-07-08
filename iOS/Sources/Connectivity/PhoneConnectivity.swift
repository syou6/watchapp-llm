import Foundation
import Observation
import WatchConnectivity

/// iPhone side of the Watch↔Phone link.
///
/// Receives `utteranceChunk`s, reassembles them per-utterance, decodes the
/// audio, and hands finished utterances to the `ConversationPipeline`. Relays
/// the pipeline's streamed reactions back to the Watch (realtime when
/// reachable, `transferUserInfo` fallback otherwise — matches the memo).
@MainActor
@Observable
final class PhoneConnectivity: NSObject {

    private(set) var isWatchReachable = false
    private(set) var isPaired = false

    private let pipeline: ConversationPipeline
    private var session: WCSession?

    /// Accumulated samples per in-flight utterance id.
    private var assembling: [UUID: [Float]] = [:]
    private var expectedNext: [UUID: Int] = [:]

    init(pipeline: ConversationPipeline) {
        self.pipeline = pipeline
        super.init()

        pipeline.onReactionUpdate = { [weak self] id, text, isFinal in
            self?.sendReaction(id: id, text: text, isFinal: isFinal)
        }

        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        self.session = session
        session.delegate = self
        session.activate()
    }

    // MARK: - Outbound (reactions → Watch)

    private func sendReaction(id: UUID, text: String, isFinal: Bool) {
        guard let session else { return }
        let message = WireMessage.reactionUpdate(id: id, text: text, isFinal: isFinal)
        guard let data = try? message.encoded() else { return }

        if session.isReachable {
            session.sendMessageData(data, replyHandler: nil) { [weak self] _ in
                // Realtime send failed; make sure the final state still lands.
                if isFinal { self?.session?.transferUserInfo(["payload": data]) }
            }
        } else if isFinal {
            // Only bother queuing the final snapshot when not reachable —
            // intermediate tokens are worthless once delivery is delayed.
            session.transferUserInfo(["payload": data])
        }
    }

    // MARK: - Inbound (audio → pipeline)

    private func ingest(_ data: Data) {
        guard let message = try? WireMessage.decode(data) else { return }
        switch message {
        case let .utteranceChunk(id, sequence, isFinal, audio):
            handleChunk(id: id, sequence: sequence, isFinal: isFinal, audio: audio)
        case .personaChanged, .reactionUpdate, .status:
            break // phone doesn't act on these
        }
    }

    private func handleChunk(id: UUID, sequence: Int, isFinal: Bool, audio: Data) {
        // Enforce in-order assembly; a gap means a dropped chunk — abandon the
        // utterance rather than react to a hole.
        let expected = expectedNext[id, default: 0]
        if sequence != expected {
            assembling[id] = nil
            expectedNext[id] = nil
            return
        }
        guard let decoded = AudioCodec.decode(audio) else { return }
        assembling[id, default: []].append(contentsOf: decoded.samples)
        expectedNext[id] = expected + 1

        if isFinal {
            let samples = assembling.removeValue(forKey: id) ?? []
            expectedNext[id] = nil
            pipeline.handleUtterance(id: id, samples: samples, sampleRate: decoded.sampleRate)
        }
    }
}

// MARK: - WCSessionDelegate

extension PhoneConnectivity: WCSessionDelegate {

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in self.refreshState(session) }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate() // re-activate for the next paired watch
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.refreshState(session) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor in self.ingest(messageData) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let data = userInfo["payload"] as? Data else { return }
        Task { @MainActor in self.ingest(data) }
    }

    @MainActor private func refreshState(_ session: WCSession) {
        isWatchReachable = session.isReachable
        isPaired = session.isPaired
    }
}
