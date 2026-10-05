import AVFoundation

enum ClipError: Error { case noBuffer }

/// Cuts a short uncompressed clip of a song into Library/Sounds, where iPhone alarms can play it.
enum Clipper {
    static let clipLength: Double = 29

    static var soundsDir: URL {
        let u = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    static func makeClip(from src: URL, start: Double, name: String) throws {
        let input = try AVAudioFile(forReading: src)
        let format = input.processingFormat
        let sr = format.sampleRate
        let total = Double(input.length)
        let startFrame = max(0, min(start * sr, total - sr))
        input.framePosition = AVAudioFramePosition(startFrame)
        let frames = AVAudioFrameCount(max(1, min(clipLength * sr, total - startFrame)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { throw ClipError.noBuffer }
        try input.read(into: buffer, frameCount: frames)

        if let ch = buffer.floatChannelData {
            let n = Int(buffer.frameLength)
            let fade = min(n / 4, Int(sr * 0.4))
            for c in 0..<Int(format.channelCount) where fade > 0 {
                for i in 0..<fade {
                    let g = Float(i) / Float(fade)
                    ch[c][i] *= g
                    ch[c][n - 1 - i] *= g
                }
            }
        }

        let dst = soundsDir.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dst)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: format.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
        let output = try AVAudioFile(forWriting: dst, settings: settings,
                                     commonFormat: format.commonFormat, interleaved: format.isInterleaved)
        try output.write(from: buffer)
    }
}
