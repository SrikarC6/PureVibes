import SwiftUI
import AVFoundation
import CoreMedia

struct Track: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    var title: String
    var artist: String
    var albumArtist: String?
    var album: String
    var artwork: NSImage?
    var trackNumber: Int?
    var discNumber: Int?
    var itunesAdvisory: String?
    var isAppleDigitalMaster: Bool = false
    var fileFormat: String?
    var codec: String?
    var bitrate: Int?
    var sampleRate: Double?
    var bitDepth: Int?
    var channels: Int?
    var fileSize: Int64?
    var duration: TimeInterval?
    
    enum QualityTier: String {
        case lossless = "Lossless", high = "High", medium = "Medium", low = "Low", unknown = "Unknown"
        var color: Color {
            switch self {
            case .lossless: return .green
            case .high: return .blue
            case .medium: return .orange
            case .low: return .red
            case .unknown: return .gray
            }
        }
    }
    
    var qualityTier: QualityTier {
        guard let format = fileFormat else { return .unknown }
        if format == "ALAC" || format == "FLAC" { return .lossless }
        if let br = bitrate {
            if br >= 320 { return .high }
            if br >= 192 { return .medium }
            return .low
        }
        return .unknown
    }
    
    private static let sharedByteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    var fileSizeString: String? {
        guard let fileSize = fileSize else { return nil }
        return Track.sharedByteFormatter.string(fromByteCount: fileSize)
    }
    
    /// Lightweight initializer — NO metadata extraction. Just path + filename.
    /// This is the primary init used during library scanning to avoid AVAsset overhead.
    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        let components = url.pathComponents
        let albumComponent = components.count >= 3 ? components[components.count - 2] : nil
        let artistComponent = components.count >= 4 ? components[components.count - 3] : nil
        self.album = (albumComponent.flatMap { $0 == "/" ? nil : $0 }) ?? "Unknown Album"
        self.artist = (artistComponent.flatMap { $0 == "/" ? nil : $0 }) ?? "Unknown Artist"
    }

    /// Full metadata load — called on-demand, NOT during library scan.
    /// Uses an autoreleasepool to ensure AVAsset is freed immediately after extraction.
    static func loadFullMetadata(from url: URL) async -> Track {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    var track = Track(url: url)
                    let asset = AVURLAsset(url: url, options: [
                        AVURLAssetPreferPreciseDurationAndTimingKey: false
                    ])

                    let metadata = asset.metadata

                    // Extract text metadata
                    track.title = metadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue
                        ?? url.deletingPathExtension().lastPathComponent
                    track.artist = metadata.first(where: { $0.commonKey == .commonKeyArtist })?.stringValue
                        ?? track.artist
                    track.album = metadata.first(where: { $0.commonKey == .commonKeyAlbumName })?.stringValue
                        ?? track.album

                    // Extract artwork
                    var foundArt: NSImage? = nil
                    if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
                       let data = item.dataValue ?? item.value as? Data {
                        foundArt = NSImage(data: data)
                    }
                    if foundArt == nil {
                        for item in metadata {
                            let id = item.identifier?.rawValue ?? ""
                            if id.contains("covr") || id.contains("APIC") || id.contains("artwork") {
                                if let data = item.dataValue ?? item.value as? Data {
                                    foundArt = NSImage(data: data)
                                    if foundArt != nil { break }
                                }
                            }
                        }
                    }
                    if foundArt == nil { foundArt = Track.findLooseArtwork(near: url) }
                    track.artwork = foundArt.flatMap { Track.downscale($0, maxSize: 400) }

                    // Extract track/disc numbers
                    track.extractTrackAndDiscNumbers(from: metadata, url: url)

                    // Extract audio format info
                    track.extractAudioFormatInfo(from: asset, url: url)
                    track.extractiTunesMetadata(from: metadata)

                    continuation.resume(returning: track)
                }
            }
        }
    }

    /// Metadata-only load — NO artwork extraction. Used during bulk library scanning
    /// to avoid the massive memory spike from decoding artwork for every track.
    /// Artwork is extracted separately, once per album, after grouping.
    static func loadMetadataOnly(from url: URL) async -> Track {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    var track = Track(url: url)
                    let asset = AVURLAsset(url: url, options: [
                        AVURLAssetPreferPreciseDurationAndTimingKey: false
                    ])

                    let metadata = asset.metadata

                    // Extract text metadata only
                    track.title = metadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue
                        ?? url.deletingPathExtension().lastPathComponent
                    track.artist = metadata.first(where: { $0.commonKey == .commonKeyArtist })?.stringValue
                        ?? track.artist
                    track.album = metadata.first(where: { $0.commonKey == .commonKeyAlbumName })?.stringValue
                        ?? track.album

                    // NO artwork extraction — that happens per-album after grouping

                    // Extract track/disc numbers
                    track.extractTrackAndDiscNumbers(from: metadata, url: url)

                    // Extract audio format info
                    track.extractAudioFormatInfo(from: asset, url: url)
                    track.extractiTunesMetadata(from: metadata)

                    continuation.resume(returning: track)
                }
            }
        }
    }

    /// Extract artwork from a single audio file URL. Used once per album after grouping.
    /// Returns a downscaled NSImage or nil. Wrapped in autoreleasepool.
    static func extractArtwork(from url: URL) async -> NSImage? {
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                autoreleasepool {
                    let asset = AVURLAsset(url: url, options: [
                        AVURLAssetPreferPreciseDurationAndTimingKey: false
                    ])
                    let metadata = asset.metadata

                    var foundArt: NSImage? = nil
                    if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }),
                       let data = item.dataValue ?? item.value as? Data {
                        foundArt = NSImage(data: data)
                    }
                    if foundArt == nil {
                        for item in metadata {
                            let id = item.identifier?.rawValue ?? ""
                            if id.contains("covr") || id.contains("APIC") || id.contains("artwork") {
                                if let data = item.dataValue ?? item.value as? Data {
                                    foundArt = NSImage(data: data)
                                    if foundArt != nil { break }
                                }
                            }
                        }
                    }
                    if foundArt == nil { foundArt = Track.findLooseArtwork(near: url) }
                    let result = foundArt.flatMap { Track.downscale($0, maxSize: 400) }
                    continuation.resume(returning: result)
                }
            }
        }
    }

    // MARK: - Metadata Extraction Helpers

    private mutating func extractTrackAndDiscNumbers(from metadata: [AVMetadataItem], url: URL) {
        // Disc Number extraction
        if let discItem = metadata.first(where: { $0.commonKey?.rawValue == "discNumber" }) ??
                          metadata.first(where: { $0.identifier?.rawValue == "TPOS" }) ??
                          metadata.first(where: { $0.identifier?.rawValue == "disk" }) {
            if let stringVal = discItem.stringValue {
                let components = stringVal.components(separatedBy: "/")
                if let first = components.first, let num = Int(first) { self.discNumber = num }
            } else if let numVal = discItem.numberValue {
                self.discNumber = numVal.intValue
            } else if let data = discItem.dataValue, data.count >= 6 {
                let discIndex = Int(data[3])
                if discIndex > 0 { self.discNumber = discIndex }
            }
        }

        // Fallback: Check file path for "CD1", "Disc 1", "Part 1" patterns
        if self.discNumber == nil {
            let path = url.path
            let pattern = "(?i)(?:cd|disc|part|vol)[\\s_.-]*(\\d+)"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: path, range: NSRange(path.startIndex..., in: path)),
               let range = Range(match.range(at: 1), in: path),
               let num = Int(path[range]) {
                self.discNumber = num
            }
        }

        // Track Number extraction (robust)
        if let trackItem = metadata.first(where: { $0.commonKey?.rawValue == "trackNumber" }) ??
                           metadata.first(where: { $0.identifier?.rawValue == "TRCK" }) ??
                           metadata.first(where: { $0.identifier?.rawValue == "trkn" }) {
            if let stringVal = trackItem.stringValue {
                let components = stringVal.components(separatedBy: "/")
                if let first = components.first, let num = Int(first) { self.trackNumber = num }
            } else if let numVal = trackItem.numberValue {
                self.trackNumber = numVal.intValue
            }
        }
    }

    private static func findLooseArtwork(near url: URL) -> NSImage? {
        let dir = url.deletingLastPathComponent()
        let names = ["cover", "folder", "album", "front", "artwork"]
        let exts = ["jpg", "jpeg", "png", "webp"]
        for name in names { for ext in exts { let file = dir.appendingPathComponent("\(name).\(ext)"); if FileManager.default.fileExists(atPath: file.path) { return NSImage(contentsOf: file) } } }
        return nil
    }

    /// Downscale an image to fit within maxSize×maxSize. Returns original if already small enough.
    private static func downscale(_ image: NSImage, maxSize: CGFloat) -> NSImage {
        let w = image.size.width
        let h = image.size.height
        guard max(w, h) > maxSize else { return image }
        let scale = maxSize / max(w, h)
        let newSize = NSSize(width: w * scale, height: h * scale)
        let resized = NSImage(size: newSize)
        resized.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: newSize),
                   from: NSRect(origin: .zero, size: image.size),
                   operation: .copy, fraction: 1.0)
        resized.unlockFocus()
        return resized
    }

    private mutating func extractAudioFormatInfo(from asset: AVAsset, url: URL) {
        if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attributes[.size] as? Int64 { self.fileSize = size }
        if let audioTrack = asset.tracks(withMediaType: .audio).first,
           let formatDesc = (audioTrack.formatDescriptions as? [CMFormatDescription])?.first,
           let basicDesc = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            self.sampleRate = basicDesc.pointee.mSampleRate
            self.bitDepth = Int(basicDesc.pointee.mBitsPerChannel)
            self.channels = Int(basicDesc.pointee.mChannelsPerFrame)
            switch basicDesc.pointee.mFormatID {
            case kAudioFormatMPEG4AAC: self.fileFormat = "AAC"; self.codec = "AAC-LC"
            case kAudioFormatAppleLossless: self.fileFormat = "ALAC"; self.codec = "Apple Lossless"
            case kAudioFormatMPEGLayer3: self.fileFormat = "MP3"; self.codec = "MP3"
            case kAudioFormatMPEG4AAC_HE: self.fileFormat = "AAC"; self.codec = "HE-AAC"
            case kAudioFormatLinearPCM: self.fileFormat = "PCM"; self.codec = "Linear PCM"
            default: self.fileFormat = "Other"; self.codec = "Unknown"
            }
            let estimatedRate = audioTrack.estimatedDataRate
            if estimatedRate > 0 { self.bitrate = Int(estimatedRate / 1000) }
            else if let fileSize = self.fileSize, let duration = self.duration, duration > 0 {
                self.bitrate = Int((Double(fileSize * 8) / duration) / 1000)
            }
        }
    }

    private mutating func extractiTunesMetadata(from metadata: [AVMetadataItem]) {
        var hasFlvr2 = false, hasAppleID = false, hasCatalogNumber = false, hasOwner = false
        for item in metadata {
            if let key = item.identifier?.rawValue {
                if key.contains("flvr") {
                    if let str = item.stringValue, str.hasPrefix("2:") { hasFlvr2 = true }
                    else if item.numberValue?.intValue == 2 { hasFlvr2 = true }
                }
                if key.contains("atID") { hasAppleID = true }
                if key.contains("cnID") { hasCatalogNumber = true }
                if key.contains("ownr") { hasOwner = true }
                if key.contains("rtng"), let val = item.numberValue?.intValue { self.itunesAdvisory = (val == 1 || val == 4) ? "Explicit" : "Clean" }
                if key.contains("trkn") || key.contains("disk") {
                    if let data = item.dataValue, data.count >= 8 {
                        let number = Int(data[3]) | (Int(data[2]) << 8)
                        if key.contains("trkn") { self.trackNumber = number }
                        if key.contains("disk") { self.discNumber = number }
                    }
                }
                if key.contains("aART") { self.albumArtist = item.stringValue }
            }
        }
        if hasFlvr2 || (hasAppleID && hasCatalogNumber) || hasOwner { self.isAppleDigitalMaster = true }
    }

    static func == (lhs: Track, rhs: Track) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    /// Async factory — uses full metadata extraction with autoreleasepool.
    static func load(from url: URL) async -> Track {
        await loadFullMetadata(from: url)
    }

    /// Backward-compatible alias for lightweight init (identical to init(url:) now).
    init(stubUrl url: URL) {
        self.init(url: url)
    }
}

struct TrackStub: Identifiable {
    let id = UUID()
    let url: URL
    let title: String
    let cachedTrack: Track?
    
    init(url: URL, cachedTrack: Track? = nil) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        self.cachedTrack = cachedTrack
    }
}
