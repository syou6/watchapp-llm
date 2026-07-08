import Foundation

/// Wire format shared by the Watch client and the iPhone brain.
///
/// Kept deliberately small and `Codable` so it survives both the realtime
/// `WCSession.sendMessageData` path and the `transferUserInfo` fallback when
/// the phone is not reachable.
enum WireMessage: Codable, Sendable {

    /// A captured utterance shipped Watch → iPhone.
    ///
    /// `audio` is a compressed chunk (see `AudioCodec`). `sequence` lets the
    /// receiver reassemble multi-chunk utterances in order; `isFinal` marks the
    /// last chunk of one utterance (VAD saw end-of-speech).
    case utteranceChunk(id: UUID, sequence: Int, isFinal: Bool, audio: Data)

    /// A streamed reaction token/snapshot shipped iPhone → Watch.
    ///
    /// `text` is the *cumulative* reaction so far (Foundation Models streams
    /// snapshots, not deltas), so the Watch can just replace what it shows.
    case reactionUpdate(id: UUID, text: String, isFinal: Bool)

    /// iPhone → Watch: which persona is currently active, for the UI.
    case personaChanged(id: String)

    /// Either side: a human-readable status/error to surface in the UI.
    case status(String)
}

extension WireMessage {
    /// JSON is plenty for these small payloads and keeps the format debuggable.
    static let encoder = JSONEncoder()
    static let decoder = JSONDecoder()

    func encoded() throws -> Data { try Self.encoder.encode(self) }

    static func decode(_ data: Data) throws -> WireMessage {
        try decoder.decode(WireMessage.self, from: data)
    }
}
