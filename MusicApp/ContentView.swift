//
//  ContentView.swift
//  MusicPlayer
//
//  Created by Srikar on 28/01/2026.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import Combine
import CoreMedia
import AppKit

extension NSImage {
    func dominantColor() -> Color {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .black }
        
        let width = 50
        let height = 50
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        guard let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return .black }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Simple average calculation
        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        let pixelCount = CGFloat(width * height)
        
        for i in stride(from: 0, to: rawData.count, by: 4) {
            totalR += CGFloat(rawData[i])
            totalG += CGFloat(rawData[i+1])
            totalB += CGFloat(rawData[i+2])
        }
        
        return Color(red: Double(totalR / pixelCount / 255.0),
                     green: Double(totalG / pixelCount / 255.0),
                     blue: Double(totalB / pixelCount / 255.0))
    }
    
    /// Returns a downscaled copy cached by pointer identity. Safe to call repeatedly.
    private static let thumbnailCache = NSCache<NSImage, NSImage>()
    
    func thumbnail(maxSize: CGFloat = 100) -> NSImage {
        if let cached = NSImage.thumbnailCache.object(forKey: self) { return cached }
        let scale = min(maxSize / max(size.width, 1), maxSize / max(size.height, 1), 1.0)
        if scale >= 1.0 { return self }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        NSImage.thumbnailCache.setObject(thumb, forKey: self)
        return thumb
    }
}

// MARK: - AI Animation Models

enum AppleMusicAnimationStyle: String, Codable {
    case kenBurns = "ken_burns"
    case parallax = "parallax"
    case ambientGlow = "ambient_glow"
    case none = "none"
}

struct AnimationParameters: Hashable, Equatable {
    let duration: Double
    let intensity: Double
    let focalPoint: CGPoint
    let shouldLoop: Bool
    let shouldStrobe: Bool
}

struct AnimationDecision: Hashable, Equatable {
    let style: AppleMusicAnimationStyle
    let parameters: AnimationParameters
    let reasoning: String?
}

struct GeminiAnalysisResult: Codable {
    let style: String
    let duration: Double
    let intensity: Double
    let focalPoint: FocalPoint
    let shouldStrobe: Bool?
    let reasoning: String
    let confidence: Double
    struct FocalPoint: Codable { let x: Double; let y: Double }
}

// MARK: - Models & Helpers

enum LoopMode {
    case off, single, queue
}

class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    var onDecodeError: (Error?) -> Void = { _ in }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { if flag { onFinish() } }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onDecodeError(error) }
}

struct VisualEffectView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.state = .active
        view.material = .underWindowBackground
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.styleMask.insert(.fullSizeContentView)
                window.isMovableByWindowBackground = false // Changed to false to fix scrubbing
                window.isMovable = true // Ensure window itself is movable
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct Album: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String 
    let albumArtist: String?
    let artwork: NSImage?
    var tracks: [Track]
    var animationDecision: AnimationDecision?
    var isAnalyzing: Bool = false
    var cachedColor: Color? // Cache the dominant color
    var isAppleDigitalMaster: Bool { tracks.contains(where: { $0.isAppleDigitalMaster }) }
    static func == (lhs: Album, rhs: Album) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

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
    
    var fileSizeString: String? {
        guard let fileSize = fileSize else { return nil }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
    
    init(url: URL) {
        self.url = url
        let asset = AVAsset(url: url)
        let metadata = asset.metadata
        self.title = metadata.first(where: { $0.commonKey == .commonKeyTitle })?.stringValue ?? url.deletingPathExtension().lastPathComponent
        self.artist = metadata.first(where: { $0.commonKey == .commonKeyArtist })?.stringValue ?? "Unknown Artist"
        self.album = metadata.first(where: { $0.commonKey == .commonKeyAlbumName })?.stringValue ?? "Unknown Album"
        
        var foundArt: NSImage? = nil
        if let item = metadata.first(where: { $0.commonKey == .commonKeyArtwork }), let data = item.dataValue ?? item.value as? Data {
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
        self.artwork = foundArt
        // Disc Number extraction
        if let discItem = metadata.first(where: { $0.commonKey?.rawValue == "discNumber" }) ?? 
                          metadata.first(where: { $0.identifier?.rawValue == "TPOS" }) ??
                          metadata.first(where: { $0.identifier?.rawValue == "disk" }) {
            if let stringVal = discItem.stringValue {
                // Handle "1/2" format
                let components = stringVal.components(separatedBy: "/")
                if let first = components.first, let num = Int(first) { self.discNumber = num }
            } else if let numVal = discItem.numberValue {
                self.discNumber = numVal.intValue
            } else if let data = discItem.dataValue, data.count >= 6 {
                 // iTunes 'disk' atom is usually 6 or 8 bytes: 00 00 [Disc Index 2 bytes] [Disc Count 2 bytes]
                 // Reading byte at index 3 (0-based) usually gives the number for standard 1-255 discs
                 let discIndex = Int(data[3])
                 if discIndex > 0 { self.discNumber = discIndex }
            }
        }
        
        // Fallback: Check file path for "CD1", "Disc 1", "Part 1" patterns
        if self.discNumber == nil {
            let path = url.path
            // Regex for CD/Disc N
            // Simplistic check for common folder names
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

        extractAudioFormatInfo(from: asset, url: url)
        extractiTunesMetadata(from: metadata)
    }
    
    private static func findLooseArtwork(near url: URL) -> NSImage? {
        let dir = url.deletingLastPathComponent()
        let names = ["cover", "folder", "album", "front", "artwork"]
        let exts = ["jpg", "jpeg", "png", "webp"]
        for name in names { for ext in exts { let file = dir.appendingPathComponent("\(name).\(ext)"); if FileManager.default.fileExists(atPath: file.path) { return NSImage(contentsOf: file) } } }
        return nil
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
}

// MARK: - AI Analyzer

class AlbumCoverAnalyzer {
    private let apiKey: String
    
    init(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func analyze(album: Album, completion: @escaping (AnimationDecision?, String?) -> Void) {
        guard !apiKey.isEmpty else { completion(nil, "API Key missing"); return }
        
        guard let artwork = album.artwork,
              let tiffData = artwork.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let imageData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
            completion(nil, "Image processing failed"); return
        }
        let base64Image = imageData.base64EncodedString()
        let prompt = """
        You are an expert at analyzing album cover artwork to determine the perfect animation style.
        
        CRITICAL GOAL: The animation must be IMMEDIATELY VISIBLE and OBVIOUS to the naked eye.
        Do NOT be subtle. We want "Pop" and "Depth" without being cartoonish.
        
        MANDATORY CONSTRAINT: If the album cover contains TEXT (Title, Artist), you MUST choose a style or parameters that KEEP THE TEXT STATIONARY or readable. Do NOT warp or crop text.
        
        Styles:
        1. KEN_BURNS: Deep, noticeable breathing/scanning. Use for portraits where the subject is clear.
        2. PARALLAX: HIGH-IMPACT 3D PERSPECTIVE SHIFT.
           - The goal is to make the subject feel DETACHED from the background.
           - Different layers must appear to move independently in opposing directions.
           - Do NOT just zoom. We want a "holographic" wobble effect.
           - Use for: Images with clear foreground/background separation.
           - SPECIAL INSTRUCTION: If the image contains a VERY BRIGHT light source (Sun, lightbulb, neon, lens flare), set 'shouldStrobe' to true.
        3. AMBIENT_GLOW: Strong, visible pulse of light and blur. For abstract art.
        4. NONE: Text-only or extremely cluttered images.
        
        Analyze image and return ONLY JSON:
        {"style": "ken_burns"|"parallax"|"ambient_glow"|"none", "duration": <15-25>, "intensity": <0.15-0.25>, "focalPoint": {"x": <0-1>, "y": <0-1>}, "shouldStrobe": <true/false>, "reasoning": "...", "confidence": 0.9}
        """
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/gemini-3-flash-preview:generateContent?key=\(apiKey)") else { completion(nil, "Invalid URL"); return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = ["contents": [["parts": [["text": prompt], ["inline_data": ["mime_type": "image/jpeg", "data": base64Image]]]]], "generationConfig": ["response_mime_type": "application/json", "temperature": 0.3]]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error = error { completion(nil, error.localizedDescription); return }
            
            guard let data = data else { completion(nil, "No data received"); return }
            
            if let jsonString = String(data: data, encoding: .utf8) {
                // Check for API errors first
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let errorObj = json["error"] as? [String: Any],
                   let message = errorObj["message"] as? String {
                    print("Gemini API Error: \(message)")
                    completion(nil, "API Error: \(message)")
                    return
                }
                
                // Debug logging
                print("Gemini Raw Response: \(jsonString)")
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let candidates = json["candidates"] as? [[String: Any]], let first = candidates.first,
                  let content = first["content"] as? [String: Any], let parts = content["parts"] as? [[String: Any]],
                  var text = parts.first?["text"] as? String else { completion(nil, "Invalid Response Structure"); return }
            
            text = text.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let resData = text.data(using: .utf8), let res = try? JSONDecoder().decode(GeminiAnalysisResult.self, from: resData) {
                let style = AppleMusicAnimationStyle(rawValue: res.style) ?? .kenBurns
                print("AI Decision for \(album.title): \(style.rawValue) - \(res.reasoning)")
                completion(AnimationDecision(style: style, parameters: AnimationParameters(duration: res.duration, intensity: res.intensity, focalPoint: CGPoint(x: res.focalPoint.x, y: res.focalPoint.y), shouldLoop: true, shouldStrobe: res.shouldStrobe ?? false), reasoning: res.reasoning), nil)
            } else { completion(nil, "JSON Parse Error") }
        }.resume()
    }
}

// MARK: - Player Logic

import MediaPlayer

struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    let track: Track
}

@MainActor
class MusicPlayer: ObservableObject {
    @Published var apiKey: String = UserDefaults.standard.string(forKey: "gemini_api_key") ?? "" {
        didSet { UserDefaults.standard.set(apiKey, forKey: "gemini_api_key") }
    }
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentTrack: Track?
    @Published var queue: [QueueItem] = [] // Updated to use wrapper
    @Published var currentIndex: Int = 0
    @Published var favorites: [UUID] = [] // Changed from Set to Array for ordering
    @Published var loopMode: LoopMode = .off
    @Published var isShuffled = false
    @Published var isAlbumContext = false // Track if we are playing a fixed album
    
    func toggleFavorite(track: Track) {
        if let index = favorites.firstIndex(of: track.id) {
            favorites.remove(at: index)
        } else {
            favorites.append(track.id)
        }
    }
    
    func isFavorite(_ track: Track) -> Bool {
        return favorites.contains(track.id)
    }
    
    func moveFavorites(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
    }
    
    @Published var albums: [Album] = []
    @Published var allTracks: [Track] = []
    @Published var analyzedCount: Int = 0
    @Published var totalToAnalyze: Int = 0
    @Published var analysisError: String?
    @Published var currentWaveform: [CGFloat] = Array(repeating: 0.3, count: 60) // Actual waveform data
    private var originalQueue: [QueueItem] = []
    var isScrubbing = false
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private let playerDelegate = PlayerDelegate()
    
    init() { 
        playerDelegate.onFinish = { [weak self] in Task { @MainActor in self?.handleTrackFinished() } }
        setupRemoteCommands()
    }
    
    // ... (Remote commands setup remains here, omitted for brevity if not replacing) ...
    
    private func extractWaveform(from url: URL, samples: Int = 60) async -> [CGFloat] {
        guard let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: UInt32(file.length)) else { return Array(repeating: 0.5, count: samples) }
        
        try? file.read(into: buffer)
        guard let floatData = buffer.floatChannelData?[0] else { return Array(repeating: 0.5, count: samples) }
        
        let totalFrames = Int(file.length)
        let chunk = totalFrames / samples
        var result: [CGFloat] = []
        
        for i in 0..<samples {
            let start = i * chunk
            let end = min(start + chunk, totalFrames)
            var rms: Float = 0
            
            // Downsample for speed (skip pixels)
            let sampleStride = Swift.max(1, (end - start) / 100) 
            var count = 0
            
            for j in Swift.stride(from: start, to: end, by: sampleStride) {
                let sample = floatData[j]
                rms += sample * sample
                count += 1
            }
            
            if count > 0 {
                let mean = rms / Float(count)
                rms = sqrt(mean)
                // Normalize and boost
                let normalized = CGFloat(Swift.min(Float(1.0), rms * 2.0)) 
                result.append(Swift.max(CGFloat(0.05), normalized)) 
            } else {
                result.append(0.2)
            }
        }
        return result
    }
    
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        
        center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.play() }
            return .success
        }
        
        center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }
        
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlayPause() }
            return .success
        }
        
        center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playNext() }
            return .success
        }
        
        center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.playPrevious() }
            return .success
        }
        
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            if let event = event as? MPChangePlaybackPositionCommandEvent {
                Task { @MainActor in self?.seek(to: event.positionTime) }
                return .success
            }
            return .commandFailed
        }
    }
    
    private func updateNowPlaying() {
        var info = [String: Any]()
        if let track = currentTrack {
            info[MPMediaItemPropertyTitle] = track.title
            info[MPMediaItemPropertyArtist] = track.artist
            info[MPMediaItemPropertyAlbumTitle] = track.album
            info[MPMediaItemPropertyPlaybackDuration] = duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player?.currentTime ?? currentTime
            info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? 1.0 : 0.0
            if let artwork = track.artwork {
                let mediaArtwork = MPMediaItemArtwork(boundsSize: artwork.size) { _ in artwork }
                info[MPMediaItemPropertyArtwork] = mediaArtwork
            }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
    func toggleLoop() { switch loopMode { case .off: loopMode = .queue; case .queue: loopMode = .single; case .single: loopMode = .off } }
    func toggleShuffle() {
        isShuffled.toggle()
        if isShuffled {
            originalQueue = queue
            if let current = currentTrack { 
                // Keep current playing, shuffle rest
                let currentItem = queue.first(where: { $0.track.id == current.id })
                let rest = queue.filter { $0.track.id != current.id }.shuffled()
                if let c = currentItem {
                    queue = [c] + rest
                    currentIndex = 0
                } else {
                    queue = rest // Should not happen if playing
                    currentIndex = 0
                }
            }
            else { queue.shuffle(); currentIndex = 0 }
        } else { 
            // Restore order
            if let current = currentTrack { 
                queue = originalQueue; 
                if let idx = queue.firstIndex(where: { $0.track.id == current.id }) { currentIndex = idx } 
            } else { 
                queue = originalQueue; currentIndex = 0 
            } 
        }
    }
    func playAlbum(_ album: Album, startingAt track: Track? = nil) {
        // Wrap tracks in QueueItem
        queue = album.tracks.map { QueueItem(track: $0) }
        originalQueue = queue; isShuffled = false
        isAlbumContext = true // Playing an album, lock queue order
        
        if let startTrack = track, let index = queue.firstIndex(where: { $0.track.id == startTrack.id }) { currentIndex = index } else { currentIndex = 0 }
        if !queue.isEmpty { loadTrack(queue[currentIndex].track); play() }
    }
    func loadTrack(_ track: Track) {
        player?.stop(); player = nil
        do { 
            player = try AVAudioPlayer(contentsOf: track.url)
            player?.delegate = playerDelegate
            player?.prepareToPlay()
            duration = player?.duration ?? 0
            currentTime = 0
            currentTrack = track
            
            // Extract waveform
            Task { [weak self] in
                let waveform = await self?.extractWaveform(from: track.url) ?? []
                await MainActor.run { self?.currentWaveform = waveform }
            }
            
            if isPlaying { player?.play(); startTimer() }
            updateNowPlaying()
        } catch { currentTrack = nil; isPlaying = false }
    }
    func togglePlayPause() { if isPlaying { pause() } else { play() } }
    func play() { player?.play(); startTimer(); isPlaying = true; updateNowPlaying() }
    func pause() { player?.pause(); timer?.invalidate(); isPlaying = false; updateNowPlaying() }
    func seek(to time: TimeInterval) { player?.currentTime = time; if !isScrubbing { currentTime = time }; updateNowPlaying() }
    func playNext() {
        guard !queue.isEmpty else { return }
        if loopMode == .single { seek(to: 0); play(); return }
        if currentIndex < queue.count - 1 { currentIndex += 1; loadTrack(queue[currentIndex].track); if isPlaying { play() } }
        else if loopMode == .queue { currentIndex = 0; loadTrack(queue[currentIndex].track); if isPlaying { play() } }
        else { isPlaying = false; player?.stop() }
    }
    func playPrevious() { 
        if currentTime > 3.0 { seek(to: 0) } 
        else if currentIndex > 0 { currentIndex -= 1; loadTrack(queue[currentIndex].track); if isPlaying { play() } } 
        else { seek(to: 0) } 
    }
    var canGoNext: Bool { currentIndex < queue.count - 1 || loopMode == .queue }
    var canGoPrevious: Bool { currentTime > 3.0 || currentIndex > 0 }
    private func startTimer() { timer?.invalidate(); timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] _ in guard let self = self, let player = self.player else { return }; if !self.isScrubbing { self.currentTime = player.currentTime } } }
    private func handleTrackFinished() { if canGoNext || loopMode == .single || loopMode == .queue { playNext() } else { isPlaying = false; timer?.invalidate() } }
    
    func moveQueueItems(from source: IndexSet, to destination: Int) { 
        queue.move(fromOffsets: source, toOffset: destination); 
        // Update currentIndex to follow the currently playing track
        if let current = currentTrack, let newIndex = queue.firstIndex(where: { $0.track.id == current.id }) { 
            currentIndex = newIndex 
        } 
    }
    func removeQueueItem(id: UUID) { 
        // ID here refers to QueueItem.id (wrapper ID)
        if let index = queue.firstIndex(where: { $0.id == id }) { 
            queue.remove(at: index); 
            // Also remove from original if not shuffled? 
            // Simplification: We don't sync originalQueue perfectly on delete for now
            if index < currentIndex { currentIndex -= 1 } 
            else if index == currentIndex { 
                if !queue.isEmpty { loadTrack(queue[max(0, currentIndex)].track) } // Stay or go prev
                else { currentTrack = nil; isPlaying = false } 
            } 
        } 
    }
    // Helper to add track to queue
    func addToQueue(_ track: Track) {
        queue.append(QueueItem(track: track))
    }
    func playNext(_ track: Track) {
        if currentIndex < queue.count {
            queue.insert(QueueItem(track: track), at: currentIndex + 1)
        } else {
            queue.append(QueueItem(track: track))
        }
    }
    
    func removeFromQueue(at index: Int) { 
        let item = queue[index]; 
        queue.remove(at: index); 
        if index < currentIndex { currentIndex -= 1 } 
        else if index == currentIndex { 
            if !queue.isEmpty { loadTrack(queue[max(0, currentIndex)].track) } 
            else { currentTrack = nil; isPlaying = false } 
        } 
    }
    func clearQueue() { queue.removeAll(); originalQueue.removeAll(); currentIndex = 0; player?.stop(); currentTrack = nil; isPlaying = false }
    func startAIAnalysis() {
        analysisError = nil
        guard !apiKey.isEmpty else { analysisError = "Gemini API Key Required"; return }
        
        let pendingIndices = albums.enumerated()
            .filter { $0.element.animationDecision == nil && !$0.element.isAnalyzing && $0.element.artwork != nil }
            .map { $0.offset }
        
        totalToAnalyze = pendingIndices.count
        analyzedCount = 0
        
        guard totalToAnalyze > 0 else { return }
        
        // Start the serial queue
        processNextAlbum(from: pendingIndices, index: 0)
    }
    
    private func processNextAlbum(from indices: [Int], index: Int) {
        // Base case: All done
        guard index < indices.count else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
                self?.totalToAnalyze = 0
                self?.analyzedCount = 0
            }
            return
        }
        
        let albumIndex = indices[index]
        let analyzer = AlbumCoverAnalyzer(apiKey: apiKey)
        
        DispatchQueue.main.async {
            self.albums[albumIndex].isAnalyzing = true
        }
        
        analyzer.analyze(album: albums[albumIndex]) { [weak self] decision, error in
            DispatchQueue.main.async {
                if let error = error {
                    // Log error but continue (unless it's a critical auth error, but we'll try to push through)
                    print("Analysis Error for \(self?.albums[albumIndex].title ?? "Unknown"): \(error)")
                    // Optional: expose error to UI briefly or just console
                }
                
                self?.albums[albumIndex].animationDecision = decision
                self?.albums[albumIndex].isAnalyzing = false
                self?.analyzedCount += 1
                
                // Wait 4 seconds before the next request to respect the ~15 RPM limit of the free tier
                // If you have a paid tier, you can reduce this delay.
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
                    self?.processNextAlbum(from: indices, index: index + 1)
                }
            }
        }
    }
}

// MARK: - UI Components

struct CustomLiquidSpinner: View {
    @State private var rotation = 0.0
    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.1), lineWidth: 4).frame(width: 40, height: 40)
            Circle().trim(from: 0, to: 0.3)
                .stroke(
                    LinearGradient(colors: [.white.opacity(0.8), .white.opacity(0.2)], startPoint: .top, endPoint: .bottom), 
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 40, height: 40)
                .rotationEffect(.degrees(rotation))
                .shadow(color: .white.opacity(0.3), radius: 4) // Glow
        }
        .onAppear { withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) { rotation = 360 } }
    }
}

struct AppleStyleAnimatedCover: View {
    let image: NSImage
    let decision: AnimationDecision
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var brightness: Double = 0.0
    @State private var blur: Double = 0.0
    @State private var rotation3D: (x: Double, y: Double) = (0, 0) // New 3D rotation state
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .scaleEffect(scale)
                    .offset(offset)
                    .brightness(brightness)
                    .blur(radius: blur)
                    .rotation3DEffect(.degrees(rotation3D.x), axis: (x: 1, y: 0, z: 0)) // Tilt X
                    .rotation3DEffect(.degrees(rotation3D.y), axis: (x: 0, y: 1, z: 0)) // Tilt Y
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
            }
            .onAppear { applyAnimation(size: geo.size) }
            .onChange(of: decision) { _ in applyAnimation(size: geo.size) }
        }
    }
    
    private func applyAnimation(size: CGSize) {
        let p = decision.parameters
        let intensity = CGFloat(p.intensity)
        let fx = CGFloat(p.focalPoint.x)
        let fy = CGFloat(p.focalPoint.y)
        let w = size.width > 0 ? size.width : 400
        let h = size.height > 0 ? size.height : 400
        
        switch decision.style {
        case .kenBurns: 
            withAnimation(.easeInOut(duration: p.duration * 0.7).repeatForever(autoreverses: true)) { 
                scale = 1.0 + (intensity * 0.85) 
                offset = CGSize(width: (fx - 0.5) * (w * 0.8) * intensity, height: -(fy - 0.5) * (h * 0.8) * intensity)
            }
        case .parallax: 
            // "Pop" without zooming: Use 3D rotation (perspective) + Opposing Pan
            withAnimation(.easeInOut(duration: p.duration * 0.85).repeatForever(autoreverses: true)) { 
                // Scale up to prevent edges showing during extreme tilt
                scale = 1.15 
                
                // STRONG Opposing Motion: Creates the feeling that the 'subject' is stuck to the glass 
                // while the background moves behind it.
                offset = CGSize(
                    width: (fx - 0.5) * (w * 0.5) * intensity, 
                    height: -(fy - 0.5) * (h * 0.5) * intensity
                )
                
                // Deep 3D Wobble (Maxed out for visibility)
                rotation3D = (
                    x: Double((fy - 0.5) * 45 * intensity), // Increased from 15 to 45
                    y: Double(-(fx - 0.5) * 45 * intensity)
                )
            }
            
            if p.shouldStrobe {
                withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true)) { // Slowed from 0.15s to 3.0s
                    brightness = 0.12 // Reduced from 0.3 to 0.12 for a faint glow
                }
            }
        case .ambientGlow: 
            withAnimation(.easeInOut(duration: p.duration * 0.5).repeatForever(autoreverses: true)) { 
                brightness = p.intensity * 0.8 
                blur = p.intensity * 8.0 
                scale = 1.0 + (intensity * 0.4) 
            }
        case .none: break
        }
    }
}

struct MarqueeView: View {
    let text: String
    let font: Font
    var artistFont: Font? = nil
    @State private var offset: CGFloat = 0
    @State private var contentWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    var body: some View {
        GeometryReader { geo in
            let isOverflowing = contentWidth > geo.size.width
            ZStack(alignment: isOverflowing ? .leading : .center) {
                HStack(spacing: 60) {
                    label.background(GeometryReader { inner in Color.clear.onAppear { contentWidth = inner.size.width }.onChange(of: inner.size.width) { contentWidth = $0 } })
                    if isOverflowing { label }
                }.offset(x: offset)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { if geo.size.width > 0 { containerWidth = geo.size.width } }
            .onChange(of: geo.size.width) { width in if width > 0 { containerWidth = width; restart() } }
            .onChange(of: text) { _ in restart() }
            .onChange(of: contentWidth) { _ in restart() }
        }.clipped()
    }
    private var label: some View { HStack(spacing: 8) { let comps = text.contains(" • ") ? text.components(separatedBy: " • ") : [text]; Text(comps[0]).font(font); if comps.count > 1 { Text("•").foregroundColor(.secondary); Text(comps[1]).font(artistFont ?? font).foregroundColor(.secondary) } }.fixedSize() }
    private func startAnimation() { guard contentWidth > containerWidth else { offset = 0; return }; let dist = contentWidth + 60; withAnimation(.linear(duration: Double(dist)/35.0).repeatForever(autoreverses: false)) { offset = -dist } }
    private func restart() { withAnimation(.none) { offset = 0 }; DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { startAnimation() } }
}

// MARK: - API Key Input View

struct APIKeyInputView: View {
    @Binding var apiKey: String
    @State private var isSecure = true
    @State private var localKey: String = ""
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "key.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                
                if isSecure {
                    SecureField("Paste Gemini API Key", text: $localKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.primary)
                        .onSubmit { apiKey = localKey }
                } else {
                    TextField("Paste Gemini API Key", text: $localKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundColor(.primary)
                        .onSubmit { apiKey = localKey }
                }
                
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye.slash" : "eye")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                if !localKey.isEmpty && localKey != apiKey {
                    Button(action: { apiKey = localKey }) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14))
                            .foregroundColor(.green)
                    }
                    .buttonStyle(.plain)
                } else if !apiKey.isEmpty {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(.green.opacity(0.5))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .onAppear { localKey = apiKey }
        .onChange(of: apiKey) { newValue in localKey = newValue }
    }
}

// MARK: - AI Animation Models

struct ExplicitBadge: View {
    var body: some View { Text("E").font(.system(size: 8, weight: .heavy)).foregroundColor(.white.opacity(0.6)).frame(width: 12, height: 12).background(RoundedRectangle(cornerRadius: 2).fill(Color.white.opacity(0.1))) }
}

struct LiquidGlassFadeMask: View {
    var body: some View { LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.1), .init(color: .black, location: 0.9), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom).allowsHitTesting(false) }
}

struct GlassButton: View {
    let icon: String
    var isActive: Bool = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 18, weight: .medium)).foregroundColor(isActive ? .accentColor : .secondary).frame(width: 48, height: 48).background(Material.ultraThinMaterial).clipShape(Circle()).overlay(Circle().stroke(LinearGradient(colors: [.white.opacity(0.6), .white.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.5)).shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        }.buttonStyle(.plain)
    }
}

// MARK: - Queue Row View (reusable component)

private struct QueueRowBackground: View {
    let isDragging: Bool
    let isHovered: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(isDragging ? Color.white.opacity(0.15) : (isHovered ? Color.white.opacity(0.08) : Color.black.opacity(0.2)))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isDragging ? Color.accentColor.opacity(0.5) : (isHovered ? Color.white.opacity(0.2) : Color.white.opacity(0.05)), lineWidth: 1)
            )
            .shadow(color: isDragging ? .black.opacity(0.3) : .clear, radius: isDragging ? 8 : 0, x: 0, y: 4)
    }
}

private struct QueueRowContent: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    let player: MusicPlayer
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Grabber Handle
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10))
                .foregroundColor(.secondary.opacity(0.3))
                .frame(width: 16)

            Text("\(index + 1)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(index < player.currentIndex ? .secondary.opacity(0.5) : .secondary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(track.title)
                        .font(.custom("Baskerville", size: 15))
                        .foregroundColor(index < player.currentIndex ? .secondary.opacity(0.5) : .primary)
                        .lineLimit(1)
                    if track.itunesAdvisory == "Explicit" { ExplicitBadge() }
                }
                Text(track.artist)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(index < player.currentIndex ? .secondary.opacity(0.3) : .secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }
}

struct QueueRow: View {
    let track: Track
    let index: Int
    let isPlaying: Bool
    let isDragging: Bool
    let player: MusicPlayer
    let onTap: () -> Void
    let onDelete: () -> Void
    let dragTranslation: CGFloat

    @State private var isHovered = false

    var body: some View {
        QueueRowContent(
            track: track,
            index: index,
            isPlaying: isPlaying,
            player: player,
            isHovered: isHovered
        )
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(QueueRowBackground(isDragging: isDragging, isHovered: isHovered))
        .scaleEffect(isDragging ? 1.02 : 1.0)
        .onHover { hovering in
             withAnimation(.easeInOut(duration: 0.2)) { isHovered = hovering }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }
}

// MARK: - QueuePopupView

struct QueuePopupView: View {
    @ObservedObject var player: MusicPlayer
    @Binding var isVisible: Bool
    @State private var selection: Set<UUID> = []
    @State private var dragTranslation: CGFloat = 0
    @State private var draggedItemID: UUID? = nil
    @State private var reorderAnimID = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text("Up Next").font(.custom("Baskerville", size: 18).bold()).foregroundColor(.white); Spacer(); Button(action: { player.clearQueue() }) { Image(systemName: "trash.fill").font(.system(size: 14)).foregroundColor(.secondary) }.buttonStyle(.plain) }.padding(16).background(Color.white.opacity(0.02))
            Divider().background(Color.white.opacity(0.1))
            if let current = player.currentTrack {
                HStack(spacing: 12) {
                    if let artwork = current.artwork { Image(nsImage: artwork.thumbnail()).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 44).cornerRadius(8) }
                    else { RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.1)).frame(width: 44, height: 44) }
                    VStack(alignment: .leading, spacing: 2) { HStack(spacing: 6) { Text(current.title).font(.custom("Baskerville", size: 15).bold()).foregroundColor(.accentColor).lineLimit(1); if current.itunesAdvisory == "Explicit" { ExplicitBadge() } }; Text(current.artist).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary).lineLimit(1) }
                    Spacer(); Image(systemName: "speaker.wave.3.fill").font(.caption).foregroundColor(.accentColor).symbolEffect(.bounce, value: player.isPlaying)
                }.padding(16).background(Color.white.opacity(0.05))
            }
            Divider().background(Color.white.opacity(0.1))
            ZStack {
                if player.queue.isEmpty {
                    VStack(spacing: 12) { Image(systemName: "music.note.list").font(.title).foregroundColor(.secondary.opacity(0.5)); Text("Queue is empty").font(.system(size: 13, design: .monospaced)).foregroundColor(.secondary) }.padding(40).frame(maxWidth: .infinity)
                }
                else {
                    QueueDragDropList(
                        player: player,
                        dragTranslation: $dragTranslation,
                        draggedItemID: $draggedItemID,
                        reorderAnimID: $reorderAnimID
                    )
                }
            }
        }.frame(width: 450, height: 500, alignment: .top).background(Material.ultraThinMaterial).clipShape(RoundedRectangle(cornerRadius: 28))
        .overlay(
            RoundedRectangle(cornerRadius: 28)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.1), .white.opacity(0.4)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15).offset(y: -15)
    }
}

// MARK: - Queue Drag and Drop List

struct QueueDragDropList: View {
    @ObservedObject var player: MusicPlayer
    @Binding var dragTranslation: CGFloat
    @Binding var draggedItemID: UUID?
    @Binding var reorderAnimID: Int
    @State private var dragStartIndex: Int? = nil

    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(player.queue) { item in
                        let index = player.queue.firstIndex(where: { $0.id == item.id }) ?? 0
                        let track = item.track
                        let isPlaying = index == player.currentIndex
                        let isDragging = draggedItemID == item.id

                        QueueRow(
                            track: track,
                            index: index,
                            isPlaying: isPlaying,
                            isDragging: isDragging,
                            player: player,
                            onTap: {
                                player.currentIndex = index
                                player.loadTrack(track)
                                player.play()
                            },
                            onDelete: { player.removeQueueItem(id: item.id) },
                            dragTranslation: isDragging ? dragTranslation : 0
                        )
                        .id(item.id)
                        .offset(y: isDragging ? dragTranslation : 0)
                        .zIndex(isDragging ? 100 : 0)
                        // CRITICAL FIX: Disable layout animation for the dragged item to prevent fighting with the drag offset
                        .transaction { transaction in
                            if isDragging {
                                transaction.animation = nil
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            player.currentIndex = index
                            player.loadTrack(track)
                            player.play()
                        }
                        .gesture(makeDragGesture(for: item, index: index))
                        .opacity(isDragging ? 0.95 : 1.0)
                        .scaleEffect(isDragging ? 1.05 : 1.0)
                    }
                }
                .padding(.vertical, 16)
                .padding(.horizontal, 12)
            }
            .coordinateSpace(name: "queueSpace")
            .scrollIndicators(.hidden)
            .animation(.spring(response: 0.45, dampingFraction: 0.75), value: player.queue)
            .mask(LiquidGlassFadeMask())
        }
    }

    private func makeDragGesture(for item: QueueItem, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 0, coordinateSpace: .named("queueSpace"))
            .onChanged { value in
                if draggedItemID == nil {
                    draggedItemID = item.id
                    dragStartIndex = player.queue.firstIndex(where: { $0.id == item.id })
                }
                
                guard let startIdx = dragStartIndex else { return }
                
                // Total distance moved in the list's space since drag began
                let totalY = value.location.y - value.startLocation.y
                
                // Effective row height (card + spacing)
                let rowHeight: CGFloat = 64 
                
                // Current index in model
                let currentIndex = player.queue.firstIndex(where: { $0.id == item.id }) ?? index
                
                // Calculate visual displacement from CURRENT model slot
                let currentModelOffset = CGFloat(currentIndex - startIdx) * rowHeight
                let displacementFromSlot = totalY - currentModelOffset
                
                // Reduce snapping strength: Only swap if moved 70% into the next slot
                let threshold = rowHeight * 0.85 
                
                if abs(displacementFromSlot) > threshold {
                    let direction = displacementFromSlot > 0 ? 1 : -1
                    let targetIndex = currentIndex + direction
                    
                    if targetIndex >= 0 && targetIndex < player.queue.count {
                        // FIX: move(from:to:) destination is "index before which items land"
                        // To move AFTER an item (dragging down), we must use targetIndex + 1
                        let moveDestination = targetIndex > currentIndex ? targetIndex + 1 : targetIndex
                        
                        withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                            player.moveQueueItems(from: IndexSet(integer: currentIndex), to: moveDestination)
                        }
                        // Feedback bump only on swap
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                        
                        // Recalculate translation immediately for the new slot
                        let newModelOffset = CGFloat(targetIndex - startIdx) * rowHeight
                        dragTranslation = totalY - newModelOffset
                    }
                } else {
                    // Update visual offset to stay under finger
                    dragTranslation = displacementFromSlot
                }
            }
            .onEnded { _ in
                withAnimation(.spring(response: 0.55, dampingFraction: 0.8)) {
                    dragTranslation = 0
                    draggedItemID = nil
                    dragStartIndex = nil
                }
            }
    }
}

// MARK: - Drag and Drop Helpers

// MARK: - Album Detail View

struct AlbumDetailView: View {
    let album: Album
    @ObservedObject var player: MusicPlayer
    var namespace: Namespace.ID
    let onBack: () -> Void
    
    private var groupedTracks: [Int: [Track]] { Dictionary(grouping: album.tracks) { $0.discNumber ?? 1 } }
    private var sortedDiscs: [Int] { groupedTracks.keys.sorted() }
    func discTracks(_ disc: Int) -> [Track] { groupedTracks[disc]?.sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) } ?? [] }
    
    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(spacing: 20) {
                AlbumCardView(album: album, player: player)
                    .matchedGeometryEffect(id: album.id, in: namespace, isSource: true)
                    .frame(width: 400, height: 400) // Fixed size
                
                VStack(spacing: 12) {
                    if album.isAppleDigitalMaster { 
                        HStack(spacing: 6) { Image(systemName: "hifispeaker.2.fill").font(.system(size: 12)); Text("Apple Digital Master").font(.system(size: 10, weight: .bold, design: .monospaced)) }.foregroundColor(.blue.opacity(0.8)).padding(.horizontal, 10).padding(.vertical, 4).background(Color.blue.opacity(0.1)).clipShape(Capsule())
                    }
                    VStack(spacing: 4) { 
                        Text(album.title).font(.custom("Baskerville", size: 32).bold()).foregroundColor(.white).multilineTextAlignment(.center)
                        Text(album.artist).font(.system(size: 18, design: .monospaced)).foregroundColor(.secondary)
                    }
                }
                Button(action: { player.playAlbum(album) }) { HStack { Image(systemName: "play.fill"); Text("Play Album").font(.system(size: 14, weight: .bold, design: .monospaced)) }.padding(.horizontal, 24).padding(.vertical, 12).background(Color.accentColor).foregroundColor(.white).clipShape(Capsule()) }.buttonStyle(.plain)
            }.frame(width: 450)
            
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) { 
                    Text("Tracks")
                        .font(.custom("Baskerville", size: 36)) 
                        .foregroundColor(.white)
                    Spacer()
                    Button(action: onBack) { Image(systemName: "xmark.circle.fill").font(.system(size: 24)).foregroundColor(.white.opacity(0.3)) }.buttonStyle(.plain) 
                }.padding(.bottom, 20)
                
                                    ScrollView { 
                                        VStack(alignment: .leading, spacing: 24) { 
                                            ForEach(sortedDiscs, id: \.self) { disc in 
                                                if sortedDiscs.count > 1 && disc != sortedDiscs.first { 
                                                    VStack(alignment: .leading, spacing: 12) {
                                                        Divider().background(Color.white.opacity(0.1))
                                                        Text("Disc \(disc)")
                                                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                                                            .foregroundColor(.secondary)
                                                    }
                                                    .padding(.top, 20)
                                                    .padding(.bottom, 10)
                                                }
                                                VStack(spacing: 0) { ForEach(discTracks(disc)) { track in TrackRow(track: track, isPlaying: player.currentTrack?.id == track.id, player: player) { player.playAlbum(album, startingAt: track) } } }
                                            }
                                        }.padding(.vertical, 40)
                                    }.scrollIndicators(.hidden).mask(LiquidGlassFadeMask())            }.frame(maxWidth: .infinity)
        }
        .padding(60)
        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 40))
        .overlay(
            RoundedRectangle(cornerRadius: 40)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.1), .white.opacity(0.4)], 
                        startPoint: .topLeading, 
                        endPoint: .bottomTrailing
                    ), 
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
    }
}

struct TrackRow: View {
    let track: Track
    let isPlaying: Bool
    @ObservedObject var player: MusicPlayer
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 0) {
                // Favorite Star
                Button(action: { 
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { 
                        player.toggleFavorite(track: track) 
                    } 
                }) {
                    Image(systemName: player.isFavorite(track) ? "star.fill" : "star")
                        .font(.system(size: 14))
                        .foregroundColor(player.isFavorite(track) ? .accentColor : .secondary.opacity(0.3))
                        .scaleEffect(player.isFavorite(track) ? 1.1 : 1.0)
                }
                .buttonStyle(.plain)
                .frame(width: 30)
                .padding(.leading, 8)
                
                Text(track.trackNumber.map { "\($0)" } ?? "-").font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary).frame(width: 30, alignment: .trailing).padding(.trailing, 20)
                HStack(spacing: 8) { Text(track.title).font(.custom("Baskerville", size: 16)).foregroundColor(isPlaying ? .accentColor : .primary).lineLimit(1); if track.itunesAdvisory == "Explicit" { ExplicitBadge() } }.frame(maxWidth: .infinity, alignment: .leading)
                MarqueeView(text: track.artist, font: .system(size: 12, design: .monospaced)).frame(maxWidth: .infinity).foregroundColor(.secondary).padding(.horizontal, 20)
                if let duration = track.duration { Text(String(format: "%d:%02d", Int(duration)/60, Int(duration)%60)).font(.system(size: 12, design: .monospaced)).foregroundColor(.secondary).frame(width: 60, alignment: .trailing) }
            }.padding(.vertical, 12).padding(.horizontal, 16).background(isPlaying ? Color.white.opacity(0.05) : Color.clear).cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: { 
                player.playNext(track)
            }) { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            
            Button(action: { player.addToQueue(track) }) { Label("Add to Queue", systemImage: "text.badge.plus") }
            
            Button(role: .destructive, action: { 
                print("Deleting track \(track.title)")
            }) { Label("Delete from Library", systemImage: "trash") }
        }
    }
}

struct LiquidStarView: View {
    @State private var shinePhase: CGFloat = 0.0
    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0
    @State private var isHovering = false
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Glass Plinth/Background
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                LinearGradient(
                                    colors: [.white.opacity(0.6), .white.opacity(0.1), .white.opacity(0.4)], 
                                    startPoint: .topLeading, 
                                    endPoint: .bottomTrailing
                                ), 
                                lineWidth: 1
                            )
                    )
                    .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                
                // The Liquid Star
                Image(systemName: "star")
                    .font(.system(size: 150, weight: .thin))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white.opacity(0.8), .white.opacity(0.3)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .shadow(color: .accentColor.opacity(0.5), radius: 20)
                    .overlay(
                        Image(systemName: "star")
                            .font(.system(size: 150, weight: .thin))
                            .foregroundColor(.white)
                            .mask(
                                Rectangle()
                                    .fill(
                                        LinearGradient(
                                            colors: [.clear, .white.opacity(0.5), .clear],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        )
                                    )
                                    .rotationEffect(.degrees(45))
                                    .offset(x: -geo.size.width + (shinePhase * geo.size.width * 3))
                            )
                    )
            }
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5)
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .onContinuousHover { phase in 
                switch phase { 
                case .active(let location): 
                    isHovering = true
                    let w = geo.size.width > 0 ? geo.size.width : 1
                    let h = geo.size.height > 0 ? geo.size.height : 1
                    tiltX = Double(-(location.y/h - 0.5) * 15)
                    tiltY = Double((location.x/w - 0.5) * 15)
                case .ended: 
                    isHovering = false; tiltX = 0; tiltY = 0 
                } 
            }
            .animation(.interactiveSpring(), value: isHovering)
            .animation(.interactiveSpring(), value: tiltX)
            .animation(.interactiveSpring(), value: tiltY)
            .onAppear {
                withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
                    shinePhase = 1.0
                }
            }
        }
    }
}

struct FavoritesDetailView: View {
    @ObservedObject var player: MusicPlayer
    let onBack: () -> Void
    
    @State private var sortOption: SortOption = .title
    @State private var hoveredTrack: Track? = nil // Track currently being hovered
    
    enum SortOption: String, CaseIterable {
        case title = "Song Name"
        case album = "Album"
        case artist = "Artist"
        case trackNumber = "Track Number" // Fallback to title if disparate albums
    }
    
    // Compute favorites list based on sort option
    var favoriteTracks: [Track] {
        let tracks = player.allTracks.filter { player.favorites.contains($0.id) }
        switch sortOption {
        case .title: return tracks.sorted { $0.title < $1.title }
        case .album: return tracks.sorted { $0.album < $1.album }
        case .artist: return tracks.sorted { $0.artist < $1.artist }
        case .trackNumber: return tracks.sorted { ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) }
        }
    }
    
    // Determine what to show on the plinth
    // Priority: Hovered Track -> Currently Playing (if favorite) -> Default Star
    var activeDisplayTrack: Track? {
        if let hovered = hoveredTrack { return hovered }
        if let current = player.currentTrack, player.favorites.contains(current.id) { return current }
        return nil
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 60) {
            VStack(spacing: 20) {
                // Dynamic Plinth
                ZStack {
                    if let track = activeDisplayTrack, let album = player.albums.first(where: { $0.title == track.album }) {
                        AlbumCardView(album: album, player: player)
                            .id(album.id) 
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    } else {
                        LiquidStarView()
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                    }
                }
                .frame(width: 400, height: 400)
                .animation(.easeInOut(duration: 0.4), value: activeDisplayTrack)
                
                VStack(spacing: 12) {
                    Text("Favorites")
                        .font(.custom("Baskerville", size: 32).bold())
                        .foregroundColor(.white)
                    Text("\(favoriteTracks.count) Songs")
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                                Button(action: {
                                    // Convert tracks to QueueItems for playback
                                    player.queue = favoriteTracks.map { QueueItem(track: $0) }
                                    player.currentIndex = 0
                                    if let first = player.queue.first { player.loadTrack(first.track); player.play() }
                                }) {
                                    HStack {
                                        Image(systemName: "play.fill")
                                        Text("Play Favorites").font(.system(size: 14, weight: .bold, design: .monospaced))
                                    }
                                    .padding(.horizontal, 24)
                                    .padding(.vertical, 12)
                                    .background(Color.accentColor)
                                    .foregroundColor(.white)
                                    .clipShape(Capsule())
                                }.buttonStyle(.plain)
                            }.frame(width: 450)
                            
                            VStack(alignment: .leading, spacing: 0) {
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Favorites")
                                            .font(.custom("Baskerville", size: 36))
                                            .foregroundColor(.white)
                                        
                                        // Sort Menu
                                        Menu {
                                            ForEach(SortOption.allCases, id: \.self) { option in
                                                Button(action: { withAnimation { sortOption = option } }) {
                                                    Label(option.rawValue, systemImage: sortOption == option ? "checkmark" : "")
                                                }
                                            }
                                        } label: {
                                            HStack(spacing: 4) {
                                                Text("Sort by: \(sortOption.rawValue)")
                                                    .font(.system(size: 12, design: .monospaced))
                                                Image(systemName: "chevron.down").font(.system(size: 10))
                                            }
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 4)
                                            .background(Color.white.opacity(0.1))
                                            .clipShape(Capsule())
                                        }
                                        .menuStyle(.borderlessButton)
                                        .frame(width: 200, alignment: .leading)
                                    }
                                    
                                    Spacer()
                                                                        // Close button removed as per request (toggle via pill icon)
                                                                    }.padding(.bottom, 20)
                                                                    
                                                                    List {
                                                                        ForEach(favoriteTracks) { track in
                                                                            TrackRow(track: track, isPlaying: player.currentTrack?.id == track.id, player: player) {
                                                                                player.loadTrack(track)
                                                                                player.play()
                                                                            }
                                                                            .listRowBackground(Color.clear)
                                                                            .listRowSeparator(.hidden)
                                                                            .background(Color.clear.contentShape(Rectangle())) 
                                                                            .onHover { isHovering in
                                                                                if isHovering { hoveredTrack = track }
                                                                                else if hoveredTrack?.id == track.id { hoveredTrack = nil }
                                                                            }
                                                                            .onDrag {
                                                                                return NSItemProvider(object: track.id.uuidString as NSString)
                                                                            }
                                                                        }
                                                                                                                                                        .onMove { source, dest in
                                                                                                                                                            player.moveFavorites(from: source, to: dest)
                                                                                                                                                            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                                                                                                                                                        }
                                                                                                                                                                }
                                                                    .listStyle(.plain)
                                                                    .scrollContentBackground(.hidden)
                                                                    .scrollIndicators(.hidden)
                                                                    .mask(LiquidGlassFadeMask())
                                                                }.frame(maxWidth: .infinity)
                                                            }
                                                            .padding(60)        .background(Material.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 40))
        .overlay(
            RoundedRectangle(cornerRadius: 40)
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.6), .white.opacity(0.1), .white.opacity(0.4)], 
                        startPoint: .topLeading, 
                        endPoint: .bottomTrailing
                    ), 
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 30, x: 0, y: 15)
        }
    }

// MARK: - Dashboard Components

struct AnalysisProgressBar: View {
    @ObservedObject var player: MusicPlayer
    
    var body: some View {
        if player.totalToAnalyze > 0 {
            HStack(spacing: 8) {
                CustomLiquidSpinner() // Use existing spinner
                    .frame(width: 16, height: 16)
                    .scaleEffect(0.4) // Scale down for pill
                
                Text("\(player.analyzedCount)/\(player.totalToAnalyze)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Material.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.1), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .transition(.scale.combined(with: .opacity))
        }
    }
}

struct MiniPlayerPill: View {
    @ObservedObject var player: MusicPlayer
    let openDirectories: () -> Void
    @Binding var showFavorites: Bool
    @Binding var showQueuePopup: Bool
    @State private var rotation: Double = 0
    @State private var spinTimer: Timer?
    @State private var localDragPct: Double? = nil
    @State private var lastDragPct: Double = 0 // For calculating scrub direction
    // Waveform States
    // Removed local amplitudes state, using player.currentWaveform directly
    @State private var loadProgress: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Main Pill
            HStack(spacing: 0) {
                // 1. Album Art Spinner
                ZStack { 
                    if let artwork = player.currentTrack?.artwork { 
                        Image(nsImage: artwork.thumbnail()).resizable().aspectRatio(contentMode: .fill).frame(width: 46, height: 46).clipShape(Circle()).rotationEffect(.degrees(rotation)) 
                    } else { 
                        Image(systemName: "music.note").frame(width: 46, height: 46).background(Color.gray.opacity(0.2)).clipShape(Circle()) 
                    } 
                }.padding(.leading, 8)
                
                // 2. Info Text
                VStack(alignment: .leading, spacing: 2) { 
                    if let track = player.currentTrack { 
                        MarqueeView(text: "\(track.title) • \(track.artist)", font: .custom("Baskerville", size: 14).bold(), artistFont: .system(size: 12, design: .monospaced))
                            .frame(width: 160, height: 20)
                            .id(track.id) // Force refresh on track change
                    } else { 
                        Text("Not Playing").font(.custom("Baskerville", size: 14)).frame(width: 160, alignment: .leading)
                    } 
                }.padding(.leading, 12)
                
                // 3. Scrubber (Waveform)
                if player.currentTrack != nil {
                    GeometryReader { geo in
                        let duration = player.duration > 0 ? player.duration : 1
                        let current = player.isScrubbing ? (localDragPct ?? 0) * duration : player.currentTime
                        let progress = min(max(0, current / duration), 1.0)
                        let handleX = geo.size.width * CGFloat(progress)
                        let amplitudes = player.currentWaveform // Use real data
                        let barCount = amplitudes.count
                        let barSpacing: CGFloat = 1.5
                        let barWidth: CGFloat = (geo.size.width - CGFloat(barCount) * barSpacing) / CGFloat(barCount)
                        
                        ZStack(alignment: .leading) {
                            // Unplayed Waveform (Dim)
                            HStack(spacing: barSpacing) {
                                ForEach(0..<barCount, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.white.opacity(0.3))
                                        .frame(width: max(1, barWidth), height: 20 * amplitudes[index])
                                }
                            }
                            
                            // Played Waveform (Bright Accent) - Masked by progress
                            HStack(spacing: barSpacing) {
                                ForEach(0..<barCount, id: \.self) { index in
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(Color.accentColor) // Use accent color
                                        .frame(width: max(1, barWidth), height: 20 * amplitudes[index])
                                }
                            }
                            .mask(
                                HStack {
                                    Rectangle()
                                        .frame(width: handleX)
                                    Spacer(minLength: 0)
                                }
                                .animation(.linear(duration: 0.02), value: handleX)
                            )
                            
                            // Loading Mask (Left to Right wipe)
                            Color.black.opacity(0.01) // Invisible touch target for drag
                                .mask(
                                    Rectangle()
                                        .scaleEffect(x: loadProgress, y: 1, anchor: .leading)
                                )
                            
                            // Handle (Draggable Bar)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(player.isScrubbing ? Color.white.opacity(0.8) : Color.white)
                                .frame(width: 4, height: 26)
                                .shadow(color: .black.opacity(0.3), radius: 2)
                                .offset(x: handleX - 2)
                                .animation(.linear(duration: 0.02), value: handleX)
                        }
                        .frame(height: 26)
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    player.isScrubbing = true
                                    let pct = min(max(0, value.location.x / geo.size.width), 1.0)
                                    localDragPct = pct 
                                    
                                    let delta = pct - lastDragPct
                                    if abs(delta) > 0.001 {
                                        let rotChange = max(-15, min(15, delta * 800)) 
                                        rotation += rotChange
                                        lastDragPct = pct
                                    }
                                }
                                .onEnded { value in
                                    let pct = min(max(0, value.location.x / geo.size.width), 1.0)
                                    player.seek(to: duration * pct)
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                        player.isScrubbing = false
                                        localDragPct = nil
                                    }
                                }
                        )
                    }
                    .frame(width: 180, height: 20)
                    .padding(.horizontal, 12)
                    .onChange(of: player.currentTrack) { _ in
                        // Animate wipe on track change
                        loadProgress = 0.0
                        withAnimation(.easeOut(duration: 0.8)) {
                            loadProgress = 1.0
                        }
                    }
                } else {
                    Spacer().frame(width: 180)
                }
                
                // 4. Playback Controls
                HStack(spacing: 16) { 
                    Button(action: { player.toggleLoop() }) { 
                        Image(systemName: loopIcon).font(.system(size: 14, design: .monospaced)).foregroundColor(loopColor) 
                    }.buttonStyle(.plain)
                    
                    Button(action: { player.playPrevious() }) { Image(systemName: "backward.fill").font(.system(size: 14)) }
                        .buttonStyle(.plain)
                        .disabled(!player.canGoPrevious)
                    
                    Button(action: { player.togglePlayPause() }) { Image(systemName: player.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 20)) }
                        .buttonStyle(.plain)
                        .disabled(player.currentTrack == nil)
                        .keyboardShortcut(.space, modifiers: [])
                    
                    Button(action: { player.playNext() }) { Image(systemName: "forward.fill").font(.system(size: 14)) }
                        .buttonStyle(.plain)
                        .disabled(!player.canGoNext)
                        
                    Button(action: { player.toggleShuffle() }) { 
                        Image(systemName: "shuffle").font(.system(size: 14, design: .monospaced)).foregroundColor(player.isShuffled ? .accentColor : .secondary) 
                    }.buttonStyle(.plain)
                    
                    // Favorite Current Track Button
                    Button(action: { 
                        if let track = player.currentTrack {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { 
                                player.toggleFavorite(track: track) 
                            }
                        }
                    }) {
                        Image(systemName: (player.currentTrack != nil && player.isFavorite(player.currentTrack!)) ? "heart.fill" : "heart")
                            .font(.system(size: 14))
                            .foregroundColor((player.currentTrack != nil && player.isFavorite(player.currentTrack!)) ? .accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .disabled(player.currentTrack == nil)
                }.padding(.horizontal, 8)
                
                // Divider removed as utility section is moving out
                Spacer().frame(width: 12)
            }
            .padding(.vertical, 8) // Reduced from 12 to 8 for balanced margins
            .background(Material.ultraThinMaterial)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1), .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
            .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
            .frame(maxWidth: 850) // Reduced width since utilities are gone
        }
        .onAppear {
            spinTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
                if player.isPlaying && !player.isScrubbing { rotation += 1 }
            }
        }
        .onDisappear {
            spinTimer?.invalidate()
            spinTimer = nil
        }
    }
    private var loopIcon: String { switch player.loopMode { case .off: return "repeat"; case .single: return "repeat.1"; case .queue: return "repeat" } }
    private var loopColor: Color { player.loopMode == .off ? .secondary : .accentColor }
}

// MARK: - Carousel Views

struct CarouselScrollTargetBehavior: ScrollTargetBehavior {
    var cardWidth: CGFloat
    var spacing: CGFloat
    
    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        let stride = cardWidth + spacing
        
        // Snap the proposed target to the nearest item
        let proposedIndex = round(target.rect.origin.x / stride)
        
        // Find the current index based on starting scroll position
        let currentIndex = round(context.originalTarget.rect.origin.x / stride)
        
        // Calculate the difference
        let delta = proposedIndex - currentIndex
        
        // Clamp the jump to a larger number (e.g., 15 items) to allow faster scrolling
        // while still preventing infinite run-away scrolls.
        let clampedDelta = max(-15, min(15, delta))
        
        // Calculate the new target index
        let newIndex = currentIndex + clampedDelta
        
        // Update the target rect to align with the new index
        target.rect.origin.x = newIndex * stride
    }
}

struct UtilityPill: View {
    let openDirectories: () -> Void
    @Binding var showFavorites: Bool
    @Binding var showQueuePopup: Bool
    @Binding var isGridView: Bool
    @Binding var showFavoritesList: Bool // Renamed binding for clarity if needed, or reuse showFavorites
    @Binding var showAPIKeyPopover: Bool
    
    var body: some View {
        HStack(spacing: 16) {
            // 1. View Toggle
            Button(action: { 
                withAnimation(.spring()) { 
                    isGridView.toggle()
                } 
            }) {
                Image(systemName: isGridView ? "rectangle.grid.1x2" : "square.grid.2x2")
                    .font(.system(size: 16))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            
            // 2. Queue Toggle
            Button(action: { withAnimation(.spring()) { showQueuePopup.toggle() } }) {
                Image(systemName: "list.bullet").font(.system(size: 16)).foregroundColor(showQueuePopup ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            // 3. Favorites List Toggle
            Button(action: { withAnimation(.spring()) { showFavorites.toggle() } }) {
                Image(systemName: showFavorites ? "star.square.fill" : "star.square").font(.system(size: 16)).foregroundColor(showFavorites ? .accentColor : .secondary)
            }.buttonStyle(.plain)
            
            // 4. Divider
            Divider().frame(height: 16).background(Color.white.opacity(0.2))
            
            // 5. Open Directory
            Button(action: openDirectories) {
                Image(systemName: "folder.badge.plus").font(.system(size: 16)).foregroundColor(.secondary)
            }.buttonStyle(.plain)
            
            // 6. API Key Settings
            Button(action: { withAnimation(.spring()) { showAPIKeyPopover.toggle() } }) {
                Image(systemName: "key.fill").font(.system(size: 14)).foregroundColor(showAPIKeyPopover ? .accentColor : .secondary)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Material.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(LinearGradient(colors: [.white.opacity(0.7), .white.opacity(0.1), .white.opacity(0.4)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
        .shadow(color: .black.opacity(0.3), radius: 15, x: 0, y: 10)
    }
}

struct AlbumCarouselView: View {
    let albums: [Album]
    @ObservedObject var player: MusicPlayer
    @Binding var currentScrollID: UUID?
    var namespace: Namespace.ID
    var selectedAlbumID: UUID?
    let onSelect: (Album) -> Void
    
    var body: some View {
        GeometryReader { fullProxy in
            let availableWidth = fullProxy.size.width
            let availableHeight = fullProxy.size.height
            
            // Dynamic card size: grows with window height, art absorbs extra space
            let bottomReserve: CGFloat = 120 // fixed space for labels + gap to pill
            let maxArtHeight = availableHeight - bottomReserve
            let cardWidth = min(max(400, maxArtHeight * 0.7), min(availableWidth * 0.55, 750))
            let spacing: CGFloat = cardWidth * 0.16
            let sidePadding = (availableWidth - cardWidth) / 2
            
            VStack(spacing: 0) {
                let carouselHeight: CGFloat = cardWidth + 160
                let topGap: CGFloat = max(8, cardWidth * 0.04)
                let bottomGap: CGFloat = max(12, availableHeight - carouselHeight - 72 - topGap)
                
                ZStack(alignment: .bottom) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: spacing) {
                            ForEach(albums) { album in
                                AlbumCardView(album: album, player: player)
                                    .matchedGeometryEffect(id: album.id, in: namespace, isSource: selectedAlbumID != album.id)
                                    .opacity(selectedAlbumID == album.id ? 0 : 1)
                                    .background(
                                        Group {
                                            if currentScrollID == album.id {
                                                (album.cachedColor ?? Color.black)
                                                    .opacity(0.6)
                                                    .frame(width: cardWidth * 0.9, height: cardWidth * 0.9)
                                                    .blur(radius: 60)
                                                    .opacity(selectedAlbumID == album.id ? 0 : 1)
                                            }
                                        }
                                    )
                                    .frame(width: cardWidth, height: cardWidth).zIndex(currentScrollID == album.id ? 100 : 0)
                                    .background(GeometryReader { geo in
                                        Color.clear.preference(key: AlbumCenterPreferenceKey.self, value: [album.id: geo.frame(in: .global).midX])
                                    })
                                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in content.scaleEffect(phase.isIdentity ? 1.1 : 0.6).opacity(phase.isIdentity ? 1.0 : 0.2).brightness(phase.isIdentity ? 0.05 : -0.5).rotation3DEffect(.degrees(phase.value * -60), axis: (x: 0, y: 1, z: 0), perspective: 0.5) }
                                    .onTapGesture { if currentScrollID == album.id { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { onSelect(album) } } else { withAnimation(.spring()) { currentScrollID = album.id } } }
                                    .id(album.id)
                            }
                        }
                        .scrollTargetLayout()
                                            .padding(.vertical, 80)
                                        }
                                        .coordinateSpace(name: "carousel") // Define coordinate space
                                        .scrollIndicators(.hidden)
                                        .contentMargins(.horizontal, sidePadding, for: .scrollContent)
                                        .scrollTargetBehavior(CarouselScrollTargetBehavior(cardWidth: cardWidth, spacing: spacing))
                                        .padding(.bottom, -20) 
                                    }
                                    .clipped() 
                                    .frame(height: carouselHeight)
                                    .onPreferenceChange(AlbumCenterPreferenceKey.self) { prefs in
                                        let center = availableWidth / 2
                                        if let closest = prefs.min(by: { abs($0.value - center) < abs($1.value - center) }) {
                                            if currentScrollID != closest.key {
                                                DispatchQueue.main.async {
                                                    currentScrollID = closest.key
                                                }
                                            }
                                        }
                                    }                
                
                if let id = currentScrollID, let album = albums.first(where: { $0.id == id }) {
                    VStack(spacing: 8) {
                        MarqueeView(text: album.title, font: .custom("Baskerville", size: 36).weight(.medium).width(.condensed), artistFont: .custom("Baskerville", size: 36).width(.condensed))
                            .frame(width: cardWidth + 100, height: 44)
                            .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
                        
                        Text(album.artist)
                            .font(.system(size: 20, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1) 
                    }
                    .padding(.top, topGap)
                    .padding(.bottom, bottomGap)
                    .id(id)
                }
            }
            .frame(width: availableWidth, height: fullProxy.size.height)
        }
    }
}

struct AlbumGridView: View {
    let albums: [Album]
    @ObservedObject var player: MusicPlayer
    let onSelect: (Album) -> Void
    
    let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 250), spacing: 40)
    ]
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 60) {
                ForEach(albums) { album in
                    VStack(spacing: 12) {
                        AlbumCardView(album: album, player: player)
                            .frame(width: 200, height: 200)
                            .onTapGesture { onSelect(album) }
                        
                        VStack(spacing: 4) {
                            MarqueeView(text: album.title, font: .custom("Baskerville", size: 16).bold(), artistFont: .custom("Baskerville", size: 16))
                                .frame(width: 200, height: 20)
                                .mask(LinearGradient(colors: [.clear, .black, .black, .clear], startPoint: .leading, endPoint: .trailing))
                            
                            Text(album.artist)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(40)
            .padding(.bottom, 120) // Clearance for pill
        }
        .scrollIndicators(.hidden)
        .mask(
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 40)
                Rectangle().fill(Color.black)
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 40)
            }
        )
    }
}

struct AlbumCardView: View {
    let album: Album
    @ObservedObject var player: MusicPlayer // Added for context menu actions
    @State private var isHovering = false
    @State private var tiltX: Double = 0
    @State private var tiltY: Double = 0
    var body: some View {
        GeometryReader { geo in
            ZStack { 
                if album.isAnalyzing { CustomLiquidSpinner().zIndex(5) }
                Group {
                    if let decision = album.animationDecision, let artwork = album.artwork { 
                        AppleStyleAnimatedCover(image: artwork, decision: decision)
                            .id(album.animationDecision)
                    }
                    else if let artwork = album.artwork { 
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill)
                    }
                    else { 
                        ZStack { 
                            RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.05)); 
                            Image(systemName: "music.note.list").font(.system(size: 100)).foregroundColor(.secondary) 
                        } 
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.1), .white.opacity(0.4)], 
                                startPoint: .topLeading, 
                                endPoint: .bottomTrailing
                            ), 
                            lineWidth: 1
                        )
                )
                .shadow(color: .black.opacity(0.4), radius: 20, x: 0, y: 10)
                
                // Glossy/Liquid Glass Sheen Overlay (Dynamic)
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(0.0), location: 0.0),
                        .init(color: .white.opacity(0.2 + (abs(tiltX) + abs(tiltY)) * 0.005), location: 0.4), 
                        .init(color: .white.opacity(0.0), location: 0.6)
                    ],
                    startPoint: UnitPoint(x: 0.0 + (tiltY * 0.02), y: 0.0 + (tiltX * 0.02)), 
                    endPoint: UnitPoint(x: 1.0 + (tiltY * 0.02), y: 1.0 + (tiltX * 0.02))   
                )
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)
            }
            .rotation3DEffect(.degrees(tiltX), axis: (x: 1, y: 0, z: 0), anchor: .center, perspective: 0.5)
            .rotation3DEffect(.degrees(tiltY), axis: (x: 0, y: 1, z: 0), anchor: .center, perspective: 0.5)
            .scaleEffect(isHovering ? 1.05 : 1.0)
            .contentShape(Rectangle().inset(by: 10))
            .onContinuousHover { phase in 
                switch phase { 
                case .active(let location): 
                    isHovering = true
                    let w = geo.size.width > 0 ? geo.size.width : 1
                    let h = geo.size.height > 0 ? geo.size.height : 1
                    tiltX = Double(-(location.y/h - 0.5) * 15)
                    tiltY = Double((location.x/w - 0.5) * 15)
                case .ended: 
                    isHovering = false; tiltX = 0; tiltY = 0 
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                } 
            }
            .animation(.interactiveSpring(), value: isHovering)
            .animation(.interactiveSpring(), value: tiltX)
            .animation(.interactiveSpring(), value: tiltY)
        }
        .onHover { isHovering in
            if isHovering {
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
            }
        }
        .contextMenu {
            Button(action: { player.playNext(album.tracks.first!) }) { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") } // Simplified: Plays first track next
            Button(action: { album.tracks.forEach { player.addToQueue($0) } }) { Label("Add to Queue", systemImage: "text.badge.plus") }
            Button(role: .destructive, action: { 
                // Dummy delete action
                print("Deleting album \(album.title)")
            }) { Label("Delete from Library", systemImage: "trash") }
        }
    }
}

struct JumpingText: View {
    let text: String
    @State private var offsets: [CGFloat]
    
    init(text: String) {
        self.text = text
        self._offsets = State(initialValue: Array(repeating: 0, count: text.count))
    }
    
    var body: some View {
        HStack(spacing: 8) { // Increased letter spacing
            ForEach(Array(text.enumerated()), id: \.offset) { index, char in
                Text(String(char))
                    .font(.custom("Baskerville", size: 80).italic()) // Much bigger font
                    .foregroundColor(.white.opacity(0.9))
                    .offset(y: offsets[index])
                    .onAppear {
                        withAnimation(.easeInOut(duration: Double.random(in: 1.5...2.5)).repeatForever(autoreverses: true)) {
                            offsets[index] = CGFloat.random(in: -10...10) // Random vertical movement
                        }
                    }
            }
        }
    }
}

struct StrobingButton: View {
    let action: () -> Void
    @State private var opacity = 0.7 // Higher start opacity for less intensity
    
    var body: some View {
        Button(action: action) {
            Text("Open Directory")
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(Capsule()) // Pill shape
                .overlay(
                    Capsule()
                        .stroke(
                            LinearGradient(
                                colors: [.white.opacity(0.6), .white.opacity(0.1), .white.opacity(0.4)], 
                                startPoint: .topLeading, 
                                endPoint: .bottomTrailing
                            ), 
                            lineWidth: 1
                        )
                )
                .shadow(color: Color.accentColor.opacity(0.3), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(.plain)
        .opacity(opacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 3.5).repeatForever(autoreverses: true)) { // Slowed from 1.2s to 3.5s
                opacity = 1.0
            }
        }
    }
}

struct CloudView: View {
    @State private var phase: CGFloat = 0
    
    var body: some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            
            var path = Path()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.5))
            
            for i in 0..<360 {
                let angle = Double(i) * .pi / 180
                // Blob shape math
                let r = min(w, h) * 0.4 + sin(Double(i) * 0.05 + phase) * 20 + cos(Double(i) * 0.1 + phase * 0.5) * 20
                let x = w * 0.5 + cos(angle) * r
                let y = h * 0.5 + sin(angle) * r
                
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
            path.closeSubpath()
            
            context.fill(path, with: .color(Color.accentColor.opacity(0.3)))
        }
        .blur(radius: 50) // Soft, cloud-like look
        .onAppear {
            withAnimation(.linear(duration: 10).repeatForever(autoreverses: false)) {
                phase = .pi * 2
            }
        }
    }
}

struct AlbumCenterPreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGFloat]
    static var defaultValue: [UUID: CGFloat] = [:]
    static func reduce(value: inout [UUID: CGFloat], nextValue: () -> [UUID: CGFloat]) {
        value.merge(nextValue()) { $1 }
    }
}

struct FaintGridBackground: View {
    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height
            let spacing: CGFloat = 25
            
            // Shimmer effect using timeline or just a static faint pattern for now to avoid high CPU
            // User asked for "shimmer", let's use a subtle opacity variation based on position
            
            for x in stride(from: 0, to: width, by: spacing) {
                for y in stride(from: 0, to: height, by: spacing) {
                    let rect = CGRect(x: x, y: y, width: 1.5, height: 1.5)
                    // Create a pseudo-random but deterministic shimmer based on position
                    // In a real animation loop this would use a timeline, but here we can just vary opacity spatially
                    let opacity = 0.1 + (sin(x * 0.01) * cos(y * 0.01) * 0.05)
                    context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(opacity)))
                }
            }
        }
        .background(Color.black) // OLED Black Base
        .allowsHitTesting(false)
    }
}

// MARK: - Main ContentView

struct ContentView: View {
    @StateObject var player = MusicPlayer()
    @State private var focusedAlbumID: UUID?
    @State private var selectedAlbum: Album? = nil
    @State private var showFavorites = false // State for favorites view
    @State private var isGridView = false // Toggle for Grid View
    @State private var showQueuePopup = false // State for queue popup
    @State private var showAPIKeyPopover = false // State for API key popover
    @State private var hasOpened = false
    @State private var mouseLocation: CGPoint = CGPoint(x: -200, y: -200) // State for grid
    @Namespace private var albumNamespace
    var body: some View {
        ZStack {
            WindowAccessor()
            
            // Background Theme Logic
            Color.black.ignoresSafeArea() // OLED Base
            
            if let artwork = currentArtwork { 
                GeometryReader { geo in 
                    Image(nsImage: artwork)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 100)
                        .opacity(0.3) 
                }
                .ignoresSafeArea()
                .drawingGroup() // Optimize rendering
                .animation(.easeInOut(duration: 0.6), value: focusedAlbumID)
                .zIndex(0) 
            }
            
            VisualEffectView().ignoresSafeArea() // Blur over the color
            
            // Background Grid
            FaintGridBackground().ignoresSafeArea().zIndex(0.5)
            
            // Queue Popup (Top Layer)
            if showQueuePopup {
                VStack {
                    Spacer()
                    QueuePopupView(player: player, isVisible: $showQueuePopup)
                        .padding(.bottom, 100) // Position above pill
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(10) // Highest Z-Index
            }
            
            VStack(spacing: 0) {
                if let error = player.analysisError {
                    Text(error).foregroundColor(.red).font(.caption).padding(8).background(Color.black.opacity(0.6)).cornerRadius(8).zIndex(2)
                }

                // Main Content Area
                GeometryReader { contentGeo in
                    ZStack(alignment: .center) { // Changed to center
                        VStack(spacing: 0) {
                            if player.albums.isEmpty { 
                                Spacer()
                                VStack(spacing: 40) {
                                    ZStack {
                                        CloudView()
                                            .frame(width: 500, height: 250)
                                            .opacity(hasOpened ? 1 : 0)
                                        
                                        JumpingText(text: "PureVibes")
                                            .opacity(hasOpened ? 1 : 0)
                                    }
                                    
                                    StrobingButton(action: openDirectories)
                                    
                                    // API Key Input
                                    VStack(spacing: 8) {
                                        Text("Gemini API Key (for AI animations)")
                                            .font(.system(size: 12, design: .monospaced))
                                            .foregroundColor(.secondary)
                                        APIKeyInputView(apiKey: $player.apiKey)
                                            .frame(maxWidth: 380)
                                    }
                                    .opacity(hasOpened ? 1 : 0)
                                }
                                .frame(maxWidth: .infinity)
                                Spacer()
                            }
                            else { 
                                if isGridView {
                                    AlbumGridView(albums: player.albums, player: player) { album in 
                                        withAnimation(.interpolatingSpring(stiffness: 120, damping: 20)) { selectedAlbum = album } 
                                    }
                                    .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)), removal: .opacity.combined(with: .scale(scale: 1.1))))
                                } else {
                                    AlbumCarouselView(albums: player.albums, player: player, currentScrollID: $focusedAlbumID, namespace: albumNamespace, selectedAlbumID: selectedAlbum?.id) { album in withAnimation(.interpolatingSpring(stiffness: 120, damping: 20)) { selectedAlbum = album } }
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .padding(.bottom, 60)
                                        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.1)), removal: .opacity.combined(with: .scale(scale: 0.9))))
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, -40) // ADDED NEGATIVE PADDING HERE TO LIFT CAROUSEL
                        .disabled(selectedAlbum != nil)
                        .opacity(selectedAlbum == nil ? 1 : 0)
                        .scaleEffect(selectedAlbum == nil ? 1 : 0.95)
                        .blur(radius: selectedAlbum == nil ? 0 : 20)

                        if let album = selectedAlbum { 
                            // Detail View Overlay
                            AlbumDetailView(album: album, player: player, namespace: albumNamespace) { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { selectedAlbum = nil } }
                                .padding(.horizontal, 40)
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity, alignment: .center) 
                                .frame(maxHeight: 650)
                                .padding(.bottom, 120) // Push up above the pill
                                .transition(
                                    .asymmetric(
                                        insertion: .opacity.combined(with: .scale(scale: 0.9)), 
                                        removal: .opacity.combined(with: .scale(scale: 0.9))
                                    )
                                )
                                .zIndex(5) 
                        }
                        
                        if showFavorites {
                            FavoritesDetailView(player: player) { withAnimation(.spring()) { showFavorites = false } }
                                .padding(.horizontal, 40)
                                .padding(.top, 40)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .frame(maxHeight: 650) // Unified size
                                .padding(.bottom, 120) // Push up above the pill
                                .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.05)), removal: .opacity))
                                .zIndex(5) 
                        }
                    }
                }
                
                // Bottom Pill Area
            .overlay(alignment: .bottom) {
                // Bottom Control Area - Ensures main pill is perfectly centered
                if !player.albums.isEmpty {
                    ZStack {
                        // Main Player Pill (Centered)
                        MiniPlayerPill(player: player, openDirectories: openDirectories, showFavorites: $showFavorites, showQueuePopup: $showQueuePopup)
                            .scaleEffect(pillScale)
                        
                        // Utility Pill (Pushed to Right)
                        HStack {
                            Spacer()
                            UtilityPill(
                                openDirectories: openDirectories,
                                showFavorites: $showFavorites,
                                showQueuePopup: $showQueuePopup,
                                isGridView: $isGridView,
                                showFavoritesList: $showFavorites,
                                showAPIKeyPopover: $showAPIKeyPopover
                            )
                            .popover(isPresented: $showAPIKeyPopover, arrowEdge: .top) {
                                VStack(spacing: 12) {
                                    Text("Gemini API Key")
                                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                        .foregroundColor(.primary)
                                    APIKeyInputView(apiKey: $player.apiKey)
                                        .frame(width: 320)
                                }
                                .padding(16)
                            }
                            .scaleEffect(pillScale)
                            .padding(.trailing, 40) // Balance loader padding if visible
                        }
                    }
                    .padding(.bottom, 25)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }                                .overlay(alignment: .bottomTrailing) {
                                    // Floating AI Loader - Completely Independent Overlay
                                    if player.totalToAnalyze > 0 && !player.albums.isEmpty {
                                        AnalysisProgressBar(player: player)
                                            .padding(.trailing, 40)
                                            .padding(.bottom, 25 + 18) // Match pill bottom padding + offset
                                            .transition(.move(edge: .trailing).combined(with: .opacity))
                                    }
                                }            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
            .animation(.easeOut(duration: 0.8), value: player.albums.isEmpty) // Animate layout changes
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onAppear { withAnimation(.easeOut(duration: 1.2)) { hasOpened = true } }
        .onChange(of: focusedAlbumID) { _ in 
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
    }
    private var pillScale: CGFloat { NSApp.keyWindow?.frame.height ?? 700 < 600 ? 0.8 : 1.0 }
    private var currentArtwork: NSImage? { if let focusedID = focusedAlbumID, let album = player.albums.first(where: { $0.id == focusedID }) { return album.artwork }; return player.currentTrack?.artwork }
    private func openDirectories() { let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.allowsMultipleSelection = true; if panel.runModal() == .OK { loadAlbums(from: panel.urls) } }
    private func loadAlbums(from urls: [URL]) { 
        DispatchQueue.global(qos: .userInitiated).async { 
            var tracks: [Track] = []
            for url in urls { 
                if let en = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.contentTypeKey]) { 
                    for case let file as URL in en { 
                        if let type = try? file.resourceValues(forKeys: [.contentTypeKey]).contentType, type.conforms(to: .audio) { 
                            tracks.append(Track(url: file)) 
                        } 
                    } 
                } 
            }
            
            // Smart Grouping: Group by Album Name first
            let rawGroups = Dictionary(grouping: tracks) { $0.album }
            
            var albums: [Album] = []
            
            for (albumName, albumTracks) in rawGroups {
                // Determine Album Artist
                // 1. Check for explicit 'albumArtist' tag
                let explicitAlbumArtists = Set(albumTracks.compactMap { $0.albumArtist })
                
                var finalArtist: String
                if let singleArtist = explicitAlbumArtists.first, explicitAlbumArtists.count == 1 {
                    finalArtist = singleArtist
                } else {
                    // 2. Check track artists
                    let trackArtists = Set(albumTracks.map { $0.artist })
                    if trackArtists.count == 1, let first = trackArtists.first {
                        finalArtist = first
                    } else {
                        // Mixed artists, no album artist tag -> "Various Artists" or infer from majority?
                        // User likely wants "Kanye West" if he's on most tracks.
                        // Simple heuristic: Most frequent artist
                        let counts = albumTracks.map { $0.artist }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
                        finalArtist = counts.max(by: { $0.value < $1.value })?.key ?? "Various Artists"
                    }
                }
                
                // Sort tracks by disc/track number
                let sorted = albumTracks.sorted { 
                    let d1 = $0.discNumber ?? 1
                    let d2 = $1.discNumber ?? 1
                    if d1 != d2 { return d1 < d2 }
                    return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0) 
                }
                
                if let first = sorted.first {
                    // Extract color here (still in background thread)
                    let color = first.artwork?.dominantColor()
                    
                    albums.append(Album(
                        title: albumName, 
                        artist: finalArtist, // Use resolved artist
                        albumArtist: finalArtist, 
                        artwork: first.artwork, 
                        tracks: sorted,
                        cachedColor: color 
                    ))
                }
            }
            
            // Sort albums solely by Title
            let sortedAlbums = albums.sorted { $0.title < $1.title }
            
            DispatchQueue.main.async { 
                self.player.albums = sortedAlbums; 
                self.focusedAlbumID = sortedAlbums.first?.id; 
                self.player.allTracks = tracks; 
                // self.player.startAIAnalysis() // Temporarily disabled for resource testing
            } 
        } 
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Full screen on launch removed as per request
    }
}

@main 
struct MusicPlayerApp: App { 
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene { 
        WindowGroup { 
            ContentView() 
        }
        .windowStyle(.hiddenTitleBar) 
    } 
}