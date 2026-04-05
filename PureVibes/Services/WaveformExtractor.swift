import Foundation
import AVFoundation
import OSLog

private let logger = Logger(subsystem: "com.purevibes.app", category: "WaveformExtractor")

/// Extracts waveform amplitude samples from an audio file using chunked processing.
/// Does NOT allocate a buffer proportional to the full file length.
struct WaveformExtractor {
    /// Default chunk size for reading audio data — 8192 frames per read.
    private static let chunkFrameCapacity: AVAudioFrameCount = 8192

    /// Extract waveform samples from an audio file.
    /// - Parameters:
    ///   - url: The audio file URL.
    ///   - sampleCount: Number of output samples (default 60).
    /// - Returns: An array of normalized amplitude values in [0.05, 1.0].
    static func extract(from url: URL, sampleCount: Int = 60) async -> [CGFloat] {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    let result = extractSync(from: url, sampleCount: sampleCount)
                    continuation.resume(returning: result)
                }
            }
        }
    }

    /// Synchronous waveform extraction — chunked sequential processing.
    static func extractSync(from url: URL, sampleCount: Int = 60) -> [CGFloat] {
        guard let file = try? AVAudioFile(forReading: url) else {
            return Array(repeating: 0.3, count: sampleCount)
        }

        let totalFrames = Int(file.length)
        guard totalFrames > 0 else {
            return Array(repeating: 0.3, count: sampleCount)
        }

        // Create a small, fixed-size buffer for chunked reading
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: chunkFrameCapacity
        ) else {
            return Array(repeating: 0.3, count: sampleCount)
        }

        let framesPerBin = totalFrames / sampleCount
        guard framesPerBin > 0 else {
            return Array(repeating: 0.3, count: sampleCount)
        }

        // We'll accumulate squared sample values per bin
        var binSumSquares = [Float](repeating: 0, count: sampleCount)
        var binSampleCounts = [Int](repeating: 0, count: sampleCount)
        var framesRead: Int = 0

        // Read the file in small chunks
        while framesRead < totalFrames {
            do {
                buffer.frameLength = 0
                try file.read(into: buffer)
            } catch {
                break
            }

            guard buffer.frameLength > 0, let floatData = buffer.floatChannelData?[0] else {
                break
            }

            let chunkLen = Int(buffer.frameLength)
            // Stride through the chunk — sample every Nth frame for efficiency
            let stride = Swift.max(1, chunkLen / 100)

            for j in Swift.stride(from: 0, to: chunkLen, by: stride) {
                let globalFrame = framesRead + j
                let binIndex = Swift.min(globalFrame / framesPerBin, sampleCount - 1)
                let sample = floatData[j]
                binSumSquares[binIndex] += sample * sample
                binSampleCounts[binIndex] += 1
            }

            framesRead += chunkLen
        }

        // Convert accumulated RMS values to normalized amplitudes
        var result = [CGFloat](repeating: 0.2, count: sampleCount)
        for i in 0..<sampleCount {
            if binSampleCounts[i] > 0 {
                let meanSquare = binSumSquares[i] / Float(binSampleCounts[i])
                let rms = sqrt(meanSquare)
                let normalized = CGFloat(Swift.min(1.0, rms * 2.0))
                result[i] = Swift.max(0.05, normalized)
            }
        }

        return result
    }
}
