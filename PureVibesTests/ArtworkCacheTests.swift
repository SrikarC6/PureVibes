import XCTest
@testable import PureVibes
import AppKit

final class ArtworkCacheTests: XCTestCase {

    override func setUp() async throws {
        await MainActor.run {
            ArtworkCache.shared.purgeAll()
        }
    }

    // MARK: - Decode-Time Downsampling

    @MainActor
    func testDecodeTimeThumbnailReturnsCorrectDimensions() throws {
        let image = createTestImage(width: 1000, height: 1000)
        let data = try XCTUnwrap(image.tiffRepresentation)

        let thumb = ArtworkCache.decodeTimeThumbnail(from: data, maxPixelSize: 100)
        XCTAssertNotNil(thumb)
        if let thumb = thumb {
            // ImageIO should constrain to 100px on the longest dimension
            XCTAssertLessThanOrEqual(max(thumb.size.width, thumb.size.height), 101)
        }
    }

    @MainActor
    func testDecodeTimeThumbnailHandlesInvalidData() {
        let junk = Data([0x00, 0x01, 0x02])
        let thumb = ArtworkCache.decodeTimeThumbnail(from: junk, maxPixelSize: 100)
        XCTAssertNil(thumb, "Invalid data should return nil")
    }

    // MARK: - Cache Behavior

    @MainActor
    func testSetAndRetrieveArtwork() throws {
        let albumID = UUID()
        let image = createTestImage(width: 200, height: 200)

        ArtworkCache.shared.setArtwork(image, forAlbumID: albumID)
        let retrieved = ArtworkCache.shared.artwork(forAlbumID: albumID)
        XCTAssertNotNil(retrieved, "Should return a cached image")
    }

    @MainActor
    func testSetArtworkDataDecodesAndStores() throws {
        let albumID = UUID()
        let image = createTestImage(width: 500, height: 500)
        let data = try XCTUnwrap(image.tiffRepresentation)

        ArtworkCache.shared.setArtwork(data: data, forAlbumID: albumID, maxPixelSize: 200)

        let retrievedImage = ArtworkCache.shared.artwork(forAlbumID: albumID)
        XCTAssertNotNil(retrievedImage, "Should have decoded and stored the image")

        let retrievedData = ArtworkCache.shared.artworkData(forAlbumID: albumID)
        XCTAssertNotNil(retrievedData, "Should have stored the compressed data")
    }

    @MainActor
    func testThumbnailGeneration() throws {
        let albumID = UUID()
        let image = createTestImage(width: 400, height: 400)
        let data = try XCTUnwrap(image.tiffRepresentation)

        ArtworkCache.shared.setArtwork(data: data, forAlbumID: albumID, maxPixelSize: 400)

        let thumb = ArtworkCache.shared.thumbnail(forAlbumID: albumID, maxSize: 50)
        XCTAssertNotNil(thumb, "Should generate a thumbnail")
    }

    // MARK: - Purge

    @MainActor
    func testPurgeClearsDecodedImages() throws {
        let albumID = UUID()
        let image = createTestImage(width: 100, height: 100)
        // Store as raw NSImage (only in imageCache, NOT in dataStore)
        ArtworkCache.shared.setArtwork(image, forAlbumID: albumID)
        XCTAssertNotNil(ArtworkCache.shared.artwork(forAlbumID: albumID))

        ArtworkCache.shared.purge()

        // Image-only entries (no data backing) should be gone
        XCTAssertNil(ArtworkCache.shared.artwork(forAlbumID: albumID), "Purge should remove image-only entries")
    }

    @MainActor
    func testPurgePreservesCompressedData() throws {
        let albumID = UUID()
        let image = createTestImage(width: 100, height: 100)
        let data = try XCTUnwrap(image.tiffRepresentation)
        ArtworkCache.shared.setArtwork(data: data, forAlbumID: albumID)

        ArtworkCache.shared.purge()

        // Compressed data should survive purge
        XCTAssertNotNil(ArtworkCache.shared.artworkData(forAlbumID: albumID), "Compressed data survives purge")
        // Artwork should re-decode on demand from preserved data
        XCTAssertNotNil(ArtworkCache.shared.artwork(forAlbumID: albumID), "Should re-decode from preserved data")
    }

    @MainActor
    func testPurgeAllClearsEverything() throws {
        let albumID = UUID()
        let image = createTestImage(width: 100, height: 100)
        let data = try XCTUnwrap(image.tiffRepresentation)
        ArtworkCache.shared.setArtwork(data: data, forAlbumID: albumID)

        ArtworkCache.shared.purgeAll()

        XCTAssertNil(ArtworkCache.shared.artworkData(forAlbumID: albumID), "purgeAll removes compressed data")
        XCTAssertNil(ArtworkCache.shared.artwork(forAlbumID: albumID), "purgeAll removes everything")
    }

    // MARK: - Dominant Color

    @MainActor
    func testDominantColorComputation() throws {
        let albumID = UUID()
        let image = createTestImage(width: 100, height: 100, color: .red)
        ArtworkCache.shared.setArtwork(image, forAlbumID: albumID)

        let color = ArtworkCache.shared.dominantColor(forAlbumID: albumID)
        XCTAssertNotNil(color, "Should compute a dominant color")
    }

    // MARK: - Helpers

    private func createTestImage(width: Int, height: Int, color: NSColor = .blue) -> NSImage {
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        color.setFill()
        NSBezierPath.fill(NSRect(x: 0, y: 0, width: width, height: height))
        image.unlockFocus()
        return image
    }
}
