import AppKit
import SwiftUI
import OSLog
import ImageIO

private let logger = Logger(subsystem: "com.purevibes.app", category: "ArtworkCache")

// MARK: - ArtworkCache
//
// The SINGLE authoritative decoded-artwork owner in the app.
// All UI reads artwork through this cache — never from Track/Album models.
//
// Architecture:
// - Compressed artwork Data is stored in a plain Dictionary (NEVER evicted —
//   this data is small ~100-300KB per album and must survive for persistence).
// - Decoded NSImage display images use NSCache (auto-evicts under memory pressure).
// - Thumbnails are a separate NSCache layer.
// - Decode-time downsampling uses ImageIO (CGImageSourceCreateThumbnailAtIndex)
//   instead of NSImage.draw/lockFocus, avoiding Retina-inflated intermediate bitmaps.

@MainActor
final class ArtworkCache: NSObject, NSCacheDelegate {
    static let shared = ArtworkCache()

    // MARK: - Storage

    /// Primary artwork cache: album UUID string → decoded NSImage (up to 400×400).
    /// NSCache — auto-evicts under RAM pressure. This is fine because images
    /// can always be re-decoded from dataStore on demand.
    private let imageCache = NSCache<NSString, NSImage>()

    /// Thumbnail cache: "\(albumID)_\(maxSize)" → downscaled NSImage.
    /// NSCache — auto-evicts under RAM pressure.
    private let thumbCache = NSCache<NSString, NSImage>()

    /// Compressed artwork data: album UUID → raw Data (JPEG/PNG/TIFF bytes).
    /// Plain Dictionary — NEVER auto-evicts. This data is the source of truth.
    /// Typical size: 100-300KB per album × 400 albums = 40-120MB.
    /// This is acceptable because it's compressed data, not decoded bitmaps.
    private var dataStore: [UUID: Data] = [:]

    /// Dominant color cache: album UUID → SwiftUI Color.
    private var colorCache: [UUID: Color] = [:]

    // MARK: - Configuration

    /// Default byte budget: 200 MB for decoded full-resolution artwork in RAM.
    static let defaultImageBudget: Int = 200 * 1024 * 1024

    /// Default byte budget for thumbnails: 64 MB.
    static let defaultThumbBudget: Int = 64 * 1024 * 1024

    // MARK: - Init

    private override init() {
        super.init()
        imageCache.delegate = self
        imageCache.totalCostLimit = Self.defaultImageBudget
        imageCache.countLimit = 0  // No count limit — cost limit is sufficient
        imageCache.name = "com.purevibes.artworkCache"

        thumbCache.totalCostLimit = Self.defaultThumbBudget
        thumbCache.countLimit = 0
        thumbCache.name = "com.purevibes.thumbCache"

        setupMemoryPressureObservers()

        logger.info("ArtworkCache initialized: \(Self.defaultImageBudget / 1024 / 1024)MB image budget, \(Self.defaultThumbBudget / 1024 / 1024)MB thumb budget")
    }

    // MARK: - Public API: Store artwork

    /// Store a decoded artwork image for an album. Cost is estimated from pixel dimensions.
    func setArtwork(_ image: NSImage, forAlbumID albumID: UUID) {
        let key = albumID.uuidString as NSString
        let cost = Self.estimateCost(for: image)
        imageCache.setObject(image, forKey: key, cost: cost)
    }

    /// Store compressed artwork Data and decode it at the given max pixel size.
    /// The compressed data is JPEG-normalized and stored in a Dictionary (never evicted, ~30-50KB each).
    /// The decoded NSImage is stored in NSCache (may be evicted, re-decoded on demand).
    func setArtwork(data: Data, forAlbumID albumID: UUID, maxPixelSize: Int = 400) {
        // Normalize to small JPEG for RAM-efficient storage.
        // Raw embedded art can be 500KB-2MB (high-res JPEG/PNG/TIFF from audio files).
        // After normalization: ~30-50KB per album.
        let normalized = Self.normalizeToJPEG(data, maxPixelSize: maxPixelSize) ?? data
        dataStore[albumID] = normalized

        // Decode and store in image cache for display
        decodeAndCacheImage(albumID: albumID, data: normalized, maxPixelSize: maxPixelSize)
    }

    /// Decode compressed data and store the resulting image in NSCache.
    /// Called during populate and on-demand when imageCache has evicted an entry.
    private func decodeAndCacheImage(albumID: UUID, data: Data, maxPixelSize: Int) {
        if let image = Self.decodeTimeThumbnail(from: data, maxPixelSize: maxPixelSize) {
            setArtwork(image, forAlbumID: albumID)
        } else if let image = NSImage(data: data) {
            // Fallback: NSImage handles more formats than ImageIO
            if let downsampled = Self.downsampleNSImage(image, maxPixelSize: maxPixelSize) {
                setArtwork(downsampled, forAlbumID: albumID)
            } else {
                setArtwork(image, forAlbumID: albumID)
            }
        }
    }

    // MARK: - Public API: Retrieve artwork

    /// Retrieve decoded artwork for an album. If the NSCache has evicted it,
    /// re-decode from the compressed data store on demand.
    func artwork(forAlbumID albumID: UUID) -> NSImage? {
        let key = albumID.uuidString as NSString

        // Fast path: already decoded in NSCache
        if let cached = imageCache.object(forKey: key) {
            return cached
        }

        // Slow path: re-decode from compressed data (NSCache evicted the decoded image)
        if let data = dataStore[albumID] {
            decodeAndCacheImage(albumID: albumID, data: data, maxPixelSize: 400)
            return imageCache.object(forKey: key)
        }

        return nil
    }

    /// Retrieve compressed artwork Data for an album (for persistence).
    /// This ALWAYS returns data if it was ever stored — it's a Dictionary, not NSCache.
    func artworkData(forAlbumID albumID: UUID) -> Data? {
        return dataStore[albumID]
    }

    /// Store compressed artwork data without decoding (used during persistence restore).
    /// Data is assumed to already be normalized (came from CoreData which stored normalized data).
    func setArtworkData(_ data: Data, forAlbumID albumID: UUID) {
        dataStore[albumID] = data
    }

    /// Check if we have artwork data for an album (without decoding).
    func hasArtworkData(forAlbumID albumID: UUID) -> Bool {
        return dataStore[albumID] != nil
    }

    // MARK: - Thumbnails

    /// Retrieve or generate a thumbnail for an album at the given max size.
    func thumbnail(forAlbumID albumID: UUID, maxSize: CGFloat = 100) -> NSImage? {
        let thumbKey = "\(albumID.uuidString)_\(Int(maxSize))" as NSString

        // Check thumb cache first
        if let cached = thumbCache.object(forKey: thumbKey) {
            return cached
        }

        // Generate from compressed data via ImageIO (preferred)
        if let compressedData = dataStore[albumID],
           let thumb = Self.decodeTimeThumbnail(from: compressedData, maxPixelSize: Int(maxSize)) {
            let cost = Self.estimateCost(for: thumb)
            thumbCache.setObject(thumb, forKey: thumbKey, cost: cost)
            return thumb
        }

        // Fallback: generate from already-decoded full artwork
        guard let fullArtwork = artwork(forAlbumID: albumID) else { return nil }
        if let thumb = Self.downsampleNSImage(fullArtwork, maxPixelSize: Int(maxSize)) {
            let cost = Self.estimateCost(for: thumb)
            thumbCache.setObject(thumb, forKey: thumbKey, cost: cost)
            return thumb
        }

        return nil
    }

    // MARK: - ImageIO Decode-Time Downsampling

    /// Decode an image from compressed Data at a specific max pixel dimension.
    /// Uses CGImageSourceCreateThumbnailAtIndex for true decode-time downsampling.
    static func decodeTimeThumbnail(from data: Data, maxPixelSize: Int) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true
        ]

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        let size = NSSize(width: cgImage.width, height: cgImage.height)
        return NSImage(cgImage: cgImage, size: size)
    }

    /// Downsample an already-decoded NSImage to a smaller size via CGImage (no lockFocus).
    static func downsampleNSImage(_ image: NSImage, maxPixelSize: Int) -> NSImage? {
        guard let tiff = image.tiffRepresentation else { return nil }
        return decodeTimeThumbnail(from: tiff, maxPixelSize: maxPixelSize)
    }

    /// Normalize artwork data to a small JPEG for RAM-efficient storage.
    /// Input: raw embedded artwork (could be JPEG/PNG/TIFF/BMP at any resolution, 500KB-2MB).
    /// Output: JPEG at maxPixelSize, quality 0.8 (~30-50KB).
    /// This is used for the in-memory dataStore — keeps total RAM low even with 1000+ albums.
    static func normalizeToJPEG(_ data: Data, maxPixelSize: Int, quality: CGFloat = 0.8) -> Data? {
        // First try ImageIO (fast, no full decode)
        if let thumb = decodeTimeThumbnail(from: data, maxPixelSize: maxPixelSize),
           let cgImage = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }

        // Fallback: NSImage decode → JPEG encode
        if let image = NSImage(data: data),
           let tiff = image.tiffRepresentation,
           let thumb = decodeTimeThumbnail(from: tiff, maxPixelSize: maxPixelSize),
           let cgImage = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let rep = NSBitmapImageRep(cgImage: cgImage)
            return rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }

        return nil
    }

    /// Estimate the decoded byte cost of an NSImage for NSCache cost tracking.
    private static func estimateCost(for image: NSImage) -> Int {
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            return cgImage.width * cgImage.height * 4
        }
        return Int(image.size.width * image.size.height * 4)
    }

    // MARK: - Dominant Color

    /// Get dominant color for an album.
    func dominantColor(forAlbumID albumID: UUID) -> Color? {
        if let cached = colorCache[albumID] {
            return cached
        }
        guard let image = artwork(forAlbumID: albumID) else { return nil }
        let color = image.dominantColor()
        colorCache[albumID] = color
        return color
    }

    /// Pre-compute dominant color.
    func ensureDominantColor(forAlbumID albumID: UUID) {
        guard colorCache[albumID] == nil else { return }
        _ = dominantColor(forAlbumID: albumID)
    }

    // MARK: - Purge

    /// Purge decoded images and thumbnails from RAM. Compressed data is preserved.
    func purge() {
        imageCache.removeAllObjects()
        thumbCache.removeAllObjects()
        colorCache.removeAll()
        logger.info("ArtworkCache purged (RAM only — \(self.dataStore.count) compressed entries preserved)")
    }

    /// Purge everything including compressed data (used on app termination or explicit reset).
    func purgeAll() {
        imageCache.removeAllObjects()
        thumbCache.removeAllObjects()
        dataStore.removeAll()
        colorCache.removeAll()
        logger.info("ArtworkCache fully purged including compressed data")
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // No-op — evicted images are re-decoded from dataStore on demand
    }

    /// Purge only thumbnails (keeps full artwork for active display).
    func purgeThumbnails() {
        thumbCache.removeAllObjects()
        logger.info("ArtworkCache thumbnails purged")
    }

    /// Trims decoded images in RAM to approximately half capacity.
    /// Compressed data is NOT affected.
    func trimToHalf() {
        let originalImageLimit = imageCache.totalCostLimit
        let originalThumbLimit = thumbCache.totalCostLimit

        imageCache.totalCostLimit = originalImageLimit / 2
        thumbCache.totalCostLimit = originalThumbLimit / 2

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.imageCache.totalCostLimit = originalImageLimit
            self.thumbCache.totalCostLimit = originalThumbLimit
        }
        logger.info("ArtworkCache RAM trimmed to half capacity")
    }

    /// Repopulate cache from album IDs and artwork data blobs.
    /// Stores compressed data in Dictionary (never evicts).
    /// Does NOT eagerly decode all images — they decode on-demand when UI requests them.
    /// Data from CoreData is already JPEG-normalized, so no re-normalization needed.
    func populate(fromDataEntries entries: [(albumID: UUID, data: Data)]) {
        dataStore.reserveCapacity(entries.count)
        for entry in entries {
            dataStore[entry.albumID] = entry.data
        }
        let totalBytes = dataStore.values.reduce(0) { $0 + $1.count }
        logger.info("ArtworkCache populated: \(entries.count) entries, \(totalBytes / 1024)KB total compressed data")
    }

    /// Number of albums with stored compressed artwork data.
    var dataStoreCount: Int { dataStore.count }

    // MARK: - Memory Pressure

    private func setupMemoryPressureObservers() {
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                logger.warning("Thermal pressure \(String(describing: state)) — purging RAM caches")
                Task { @MainActor in self?.purge() }
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            if let app = NSApp, !app.occlusionState.contains(.visible) {
                logger.info("App hidden — purging thumbnail cache")
                Task { @MainActor in self?.purgeThumbnails() }
            }
        }

        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            logger.warning("System memory pressure — purging RAM caches (data preserved)")
            Task { @MainActor in self?.purge() }
        }
        source.resume()
        self.memoryPressureSource = source
    }

    private var memoryPressureSource: DispatchSourceMemoryPressure?
}
