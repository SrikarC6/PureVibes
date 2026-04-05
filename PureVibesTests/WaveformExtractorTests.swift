import XCTest
@testable import PureVibes

final class WaveformExtractorTests: XCTestCase {

    // MARK: - Sample Count

    func testExtractSyncReturnsCorrectSampleCount() throws {
        // Use a URL for a file that doesn't exist — should return fallback waveform
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_audio_file.wav")
        let result = WaveformExtractor.extractSync(from: fakeURL, sampleCount: 60)
        XCTAssertEqual(result.count, 60, "Should return exactly the requested sample count")
    }

    func testExtractSyncReturnsCorrectCustomSampleCount() {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_audio.m4a")
        let result = WaveformExtractor.extractSync(from: fakeURL, sampleCount: 120)
        XCTAssertEqual(result.count, 120, "Should return exactly 120 samples when requested")
    }

    // MARK: - Fallback for Invalid Files

    func testExtractSyncHandlesInvalidFile() {
        let fakeURL = URL(fileURLWithPath: "/tmp/does_not_exist.flac")
        let result = WaveformExtractor.extractSync(from: fakeURL, sampleCount: 60)
        XCTAssertEqual(result.count, 60)
        // All values should be 0.3 (the fallback)
        for sample in result {
            XCTAssertEqual(sample, 0.3, accuracy: 0.001, "Invalid file should return 0.3 fallback values")
        }
    }

    // MARK: - Value Range

    func testExtractSyncValuesInRange() {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent.wav")
        let result = WaveformExtractor.extractSync(from: fakeURL, sampleCount: 60)
        for sample in result {
            XCTAssertGreaterThanOrEqual(sample, 0.0, "Samples should be >= 0")
            XCTAssertLessThanOrEqual(sample, 1.0, "Samples should be <= 1.0")
        }
    }

    // MARK: - Async extraction

    func testExtractAsyncReturnsCorrectCount() async {
        let fakeURL = URL(fileURLWithPath: "/tmp/nonexistent_audio.aiff")
        let result = await WaveformExtractor.extract(from: fakeURL, sampleCount: 30)
        XCTAssertEqual(result.count, 30)
    }
}
