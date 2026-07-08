import AVFoundation
import Foundation

/// Microphone capture on Apple Watch.
///
/// watchOS only grants sustained mic access while the app is frontmost or a
/// workout session is running (the memo's "short-on" design). This class covers
/// the frontmost case; wrap it in an `HKWorkoutSession` if you need the screen
/// to sleep. Emits 16 kHz mono `Float32` — same contract as the phone side.
final class WatchAudioCapture {

    static let sampleRate: Double = 16_000

    var onBuffer: (([Float], Double) -> Void)?

    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: WatchAudioCapture.sampleRate,
        channels: 1,
        interleaved: false
    )!

    private(set) var isRunning = false

    func start() throws {
        guard !isRunning else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false)
        isRunning = false
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        guard let converter, let onBuffer else { return }
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if consumed { status.pointee = .noDataNow; return nil }
            consumed = true
            status.pointee = .haveData
            return buffer
        }
        guard error == nil, let channel = out.floatChannelData else { return }
        let samples = Array(UnsafeBufferPointer(start: channel[0], count: Int(out.frameLength)))
        onBuffer(samples, targetFormat.sampleRate)
    }
}
