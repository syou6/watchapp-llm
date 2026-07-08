import Foundation

/// Minimal PCM packing used for the Watch → iPhone audio hop.
///
/// The capture graph produces 16 kHz mono `Float32` samples. Shipping those raw
/// is wasteful over WatchConnectivity, so we down-cast to `Int16` (halves the
/// bytes with no audible loss for speech) and prefix a tiny header carrying the
/// sample rate. This is intentionally simple — swap in Opus/AAC here later if
/// you need a further ~10x without touching call sites.
enum AudioCodec {

    /// Format tag so the decoder can evolve without breaking older payloads.
    private static let magic: UInt32 = 0x5741_5631 // "WAV1"

    static func encode(samples: [Float], sampleRate: Double) -> Data {
        var data = Data()
        data.appendLE(magic)
        data.appendLE(UInt32(sampleRate.rounded()))
        data.appendLE(UInt32(samples.count))
        data.reserveCapacity(data.count + samples.count * 2)
        for s in samples {
            let clamped = max(-1.0, min(1.0, s))
            let i = Int16(clamped * Float(Int16.max))
            data.appendLE(UInt16(bitPattern: i))
        }
        return data
    }

    struct DecodedAudio {
        let samples: [Float]
        let sampleRate: Double
    }

    static func decode(_ data: Data) -> DecodedAudio? {
        var offset = 0
        guard let tag: UInt32 = data.readLE(&offset), tag == magic,
              let rate: UInt32 = data.readLE(&offset),
              let count: UInt32 = data.readLE(&offset),
              data.count >= offset + Int(count) * 2 else { return nil }

        var samples = [Float]()
        samples.reserveCapacity(Int(count))
        for _ in 0..<Int(count) {
            guard let raw: UInt16 = data.readLE(&offset) else { return nil }
            let i = Int16(bitPattern: raw)
            samples.append(Float(i) / Float(Int16.max))
        }
        return DecodedAudio(samples: samples, sampleRate: Double(rate))
    }
}

// MARK: - Little-endian helpers

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var v = value.littleEndian
        Swift.withUnsafeBytes(of: &v) { append(contentsOf: $0) }
    }

    func readLE<T: FixedWidthInteger>(_ offset: inout Int) -> T? {
        let size = MemoryLayout<T>.size
        guard count >= offset + size else { return nil }
        let value = subdata(in: offset..<(offset + size)).withUnsafeBytes {
            $0.loadUnaligned(as: T.self)
        }
        offset += size
        return T(littleEndian: value)
    }
}
