import AppKit
import SwiftUI
import OSLog

private let logger = Logger(subsystem: "com.purevibes.app", category: "ArtworkCache")

// MARK: - ArtworkCache
//
// A centralized, NSCache-backed artwork store keyed by album ID.
// All UI should read artwork through this cache rather than from Track/Album directly.
// The cache auto-evicts under system memory pressure and can be purged manually.

@MainActor
final class ArtworkCache: NSObject, NSCacheDelegate {
    static let shared = ArtworkCache()

    // MARK: - Storage

    /// Primary artwork cache: album UUID string → full-resolution NSImage (up to 400×400).
    /// NSCache handles automatic eviction under memory pressure.
    private let imageCache = NSCache<NSString, NSImage>()

    /// Thumbnail cache: "\(albumID)_\(maxSize)" → downscaled NSImage.
    private let thumbCache = NSCache<NSString, NSImage>()

    /// Dominant color cache: album UUID → SwiftUI Color.
    /// Stored in a dictionary (not NSCache) because Color values are tiny (~48 bytes).
    private var colorCache: [UUID: Color] = [:]

    // MARK: - Configuration

    /// Default byte budget: 128 MB for full-resolution artwork.
    static let defaultByteBudget: Int = 128 * 1024 * 1024

    /// Default byte budget for thumbnails: 32 MB.
    static let defaultThumbByteBudget: Int = 32 * 1024 * 1024

    // MARK: - Init

    private init(byteBudget: Int = ArtworkCache.defaultByteBudget,
                 thumbByteBudget: Int = ArtworkCache.defaultThumbByteBudget) {
        super.init()
        imageCache.delegate = self
        imageCache.totalCostLimit = byteBudget
        imageCache.countLimit = 600
        imageCache.name = "com.purevibes.artworkCache"

        thumbCache.totalCostLimit = thumbByteBudget
        thumbCache.countLimit = 1200
        thumbCache.name = "com.purevibes.thumbCache"

        // Register for memory-related notifications
        setupMemoryPressureObservers()

        logger.info("ArtworkCache initialized with \(byteBudget / 1024 / 1024)MB image budget, \(thumbByteBudget / 1024 / 1024)MB thumb budget")
    }

    // MARK: - Public API

    /// Store artwork for an album. Cost is estimated from pixel dimensions.
    func setArtwork(_ image: NSImage, forAlbumID albumID: UUID) {
        let key = albumID.uuidString as NSString
        let cost: Int
        if let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            cost = cgImage.width * cgImage.height * 4
        } else {
            // Fallback: points-based estimate (conservative)
            cost = Int(image.size.width * image.size.height * 4)
        }
        imageCache.setObject(image, forKey: key, cost: cost)
    }

    /// Retrieve full-resolution artwork for an album (up to 400×400 as downscaled during load).
    func artwork(forAlbumID albumID: UUID) -> NSImage? {
        let key = albumID.uuidString as NSString
        return imageCache.object(forKey: key)
    }

    /// Retrieve or generate a thumbnail for an album at the given max size.
    /// Caches the result — repeated calls with the same size return the same instance.
    func thumbnail(forAlbumID albumID: UUID, maxSize: CGFloat = 100) -> NSImage? {
        let thumbKey = "\(albumID.uuidString)_\(Int(maxSize))" as NSString

        // Check thumb cache first
        if let cached = thumbCache.object(forKey: thumbKey) {
            return cached
        }

        // Generate from full artwork
        guard let fullArtwork = artwork(forAlbumID: albumID) else { return nil }
        let thumb = fullArtwork.thumbnail(maxSize: maxSize)
        let cost: Int
        if let cgImage = thumb.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            cost = cgImage.width * cgImage.height * 4
        } else {
            cost = Int(thumb.size.width * thumb.size.height * 4)
        }
        thumbCache.setObject(thumb, forKey: thumbKey, cost: cost)
        return thumb
    }

    /// Get dominant color for an album. Computed lazily on first access and cached forever
    /// (colors are tiny — ~48 bytes each, so no eviction needed).
    func dominantColor(forAlbumID albumID: UUID) -> Color? {
        // Return cached color if available
        if let cached = colorCache[albumID] {
            return cached
        }

        // Compute from artwork — this is intentionally synchronous but only called
        // for visible/focused albums (not during the load pipeline).
        guard let image = artwork(forAlbumID: albumID) else { return nil }
        let color = image.dominantColor()
        colorCache[albumID] = color
        return color
    }

    /// Pre-compute dominant color asynchronously (call from carousel on scroll).
    func ensureDominantColor(forAlbumID albumID: UUID) {
        guard colorCache[albumID] == nil else { return }
        // Compute inline — dominantColor() is fast (~1ms on a 50×50 downscale)
        _ = dominantColor(forAlbumID: albumID)
    }

    /// Purge all cached data. Called on memory pressure or user request.
    func purge() {
        imageCache.removeAllObjects()
        thumbCache.removeAllObjects()
        colorCache.removeAll()
        logger.info("ArtworkCache purged")
    }

    nonisolated func cache(_ cache: NSCache<AnyObject, AnyObject>, willEvictObject obj: Any) {
        // NSCache doesn't provide the key on eviction, so we must remove stale IDs differently.
        // The simplest correct fix: remove populatedAlbumIDs entirely and always write to cache.
    }

    /// Purge only thumbnails and colors (keeps full artwork for active display).
    func purgeThumbnails() {
        thumbCache.removeAllObjects()
        logger.info("ArtworkCache thumbnails purged")
    }

    /// Trims the cache to approximately half its capacity to free up RAM.
    func trimToHalf() {
        let originalImageLimit = imageCache.totalCostLimit
        let originalThumbLimit = thumbCache.totalCostLimit
        
        // Temporarily halve the limits to force NSCache to evict LRU entries
        imageCache.totalCostLimit = originalImageLimit / 2
        thumbCache.totalCostLimit = originalThumbLimit / 2
        
        // Restore the standard capacity on the next run loop
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            self.imageCache.totalCostLimit = originalImageLimit
            self.thumbCache.totalCostLimit = originalThumbLimit
        }
        logger.info("ArtworkCache trimmed to half capacity")
    }

    /// Repopulate cache from an array of albums (e.g., after a purge or on re-launch).
    func populate(from albums: [Album]) {
        for album in albums {
            if let art = album.artwork {
                setArtwork(art, forAlbumID: album.id)
            }
        }
    }

    // MARK: - Memory Pressure

    private func setupMemoryPressureObservers() {
        // macOS thermal state changes — purge on .serious or .critical
        NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            let state = ProcessInfo.processInfo.thermalState
            if state == .serious || state == .critical {
                logger.warning("Thermal pressure \(String(describing: state)) — purging artwork cache")
                Task { @MainActor in self?.purge() }
            }
        }

        // App entered background / hidden — purge thumbnails to reclaim memory
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

        // System memory pressure via DispatchSource (macOS equivalent of didReceiveMemoryWarning)
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            logger.warning("System memory pressure detected — purging artwork cache")
            Task { @MainActor in self?.purge() }
        }
        source.resume()
        // Store the source to prevent deallocation
        self.memoryPressureSource = source
    }

    /// Stored to prevent early deallocation of the GCD memory pressure source.
    private var memoryPressureSource: DispatchSourceMemoryPressure?
}
