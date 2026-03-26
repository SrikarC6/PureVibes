#!/usr/bin/env swift
// simulate_cache_pipeline.swift
// Simulates PureVibes' cache pipeline with sustained performance monitoring.
// Tracks memory (RSS) and CPU time at each phase and per-batch to ensure
// no single operation causes an extreme spike.
//
// Usage:  swift scripts/simulate_cache_pipeline.swift [music_directory]

import Foundation

// MARK: - Resource Monitor

struct ResourceSnapshot {
    let rssBytes: Int64       // Resident Set Size in bytes
    let userTimeMs: Double    // User CPU time in milliseconds
    let sysTimeMs: Double     // System CPU time in milliseconds
    let wallTime: Date

    static func now() -> ResourceSnapshot {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let rss = Int64(usage.ru_maxrss)  // macOS: bytes
        let userMs = Double(usage.ru_utime.tv_sec) * 1000.0
                   + Double(usage.ru_utime.tv_usec) / 1000.0
        let sysMs  = Double(usage.ru_stime.tv_sec) * 1000.0
                   + Double(usage.ru_stime.tv_usec) / 1000.0
        return ResourceSnapshot(rssBytes: rss, userTimeMs: userMs, sysTimeMs: sysMs, wallTime: Date())
    }

    var rssMB: Double { Double(rssBytes) / (1024.0 * 1024.0) }
    var totalCpuMs: Double { userTimeMs + sysTimeMs }
}

struct PhaseMeasurement {
    let name: String
    let start: ResourceSnapshot
    let end: ResourceSnapshot
    var wallSec: Double { end.wallTime.timeIntervalSince(start.wallTime) }
    var cpuDeltaMs: Double { end.totalCpuMs - start.totalCpuMs }
    var rssPeakMB: Double { end.rssMB }  // ru_maxrss is high-water mark
    var rssStartMB: Double { start.rssMB }
}

var measurements: [PhaseMeasurement] = []
var batchSnapshots: [(label: String, snap: ResourceSnapshot)] = []

// Thresholds for "extreme" usage
let memoryThresholdMB: Double = 500.0    // flag if RSS exceeds 500MB
let cpuSpikeThresholdMs: Double = 5000.0 // flag if any phase uses >5s CPU

// MARK: - Simulated Models

struct SimTrack {
    let url: URL
    var title: String
    var artist: String
    var album: String
    var trackNumber: Int?

    init(url: URL) {
        self.url = url
        self.title = url.deletingPathExtension().lastPathComponent
        let comps = url.pathComponents
        self.album  = comps.count >= 3 ? comps[comps.count - 2] : "Unknown Album"
        self.artist = comps.count >= 4 ? comps[comps.count - 3] : "Unknown Artist"
    }
}

struct SimAlbum {
    let title: String
    let artist: String
    var tracks: [SimTrack]
    var hasArtwork: Bool = false
}

// MARK: - Phase 1: File Enumeration

func enumerateAudioFiles(in directory: URL) -> [URL] {
    let exts: Set<String> = ["mp3", "m4a", "aac", "flac", "alac", "wav", "aiff", "ogg", "wma"]
    guard let enumerator = FileManager.default.enumerator(
        at: directory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    ) else { return [] }
    var results: [URL] = []
    for case let fileURL as URL in enumerator {
        if exts.contains(fileURL.pathExtension.lowercased()) {
            results.append(fileURL)
        }
    }
    return results
}

// MARK: - Phase 2: Metadata-Only Extraction (simulated)

func loadMetadataOnly(from urls: [URL]) -> [SimTrack] {
    return urls.map { SimTrack(url: $0) }
}

// MARK: - Phase 3: Group Tracks into Albums

func groupIntoAlbums(_ tracks: [SimTrack]) -> [SimAlbum] {
    let grouped = Dictionary(grouping: tracks) { $0.album }
    var albums: [SimAlbum] = []
    for (name, albumTracks) in grouped {
        let artist = albumTracks.first?.artist ?? "Unknown"
        let sorted = albumTracks.sorted {
            ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
        }
        albums.append(SimAlbum(title: name, artist: artist, tracks: sorted))
    }
    albums.sort { $0.title < $1.title }
    return albums
}

// MARK: - Phase 4: Per-Album Artwork (simulated)

func extractArtworkPerAlbum(_ albums: inout [SimAlbum]) {
    let names = ["cover", "folder", "album", "front", "artwork"]
    let exts  = ["jpg", "jpeg", "png", "webp"]

    for i in albums.indices {
        guard let first = albums[i].tracks.first else { continue }
        let dir = first.url.deletingLastPathComponent()
        for name in names {
            for ext in exts {
                let path = dir.appendingPathComponent(name + "." + ext)
                if FileManager.default.fileExists(atPath: path.path) {
                    albums[i].hasArtwork = true
                    break
                }
            }
            if albums[i].hasArtwork { break }
        }
    }
}

// MARK: - Phase 5: Cache Save Simulation (with batch monitoring)

func simulateCacheSave(_ albums: [SimAlbum]) {
    let batchSize = 20
    var totalTracks = 0
    var batchStart = ResourceSnapshot.now()

    for (i, album) in albums.enumerated() {
        totalTracks += album.tracks.count

        if (i + 1) % batchSize == 0 {
            let batchEnd = ResourceSnapshot.now()
            let label = "batch_\(i + 1 - batchSize + 1)-\(i + 1)"
            batchSnapshots.append((label: label, snap: batchEnd))

            let batchCpuMs = batchEnd.totalCpuMs - batchStart.totalCpuMs
            let batchWallMs = batchEnd.wallTime.timeIntervalSince(batchStart.wallTime) * 1000
            print("  Batch \(i + 1)/\(albums.count): \(totalTracks) tracks, " +
                  "CPU: \(String(format: "%.1f", batchCpuMs))ms, " +
                  "RSS: \(String(format: "%.1f", batchEnd.rssMB))MB, " +
                  "wall: \(String(format: "%.1f", batchWallMs))ms")

            batchStart = batchEnd
        }
    }
    print("  Final: \(albums.count) albums, \(totalTracks) tracks")
}

// MARK: - Main

let args = CommandLine.arguments
let musicDir: URL
if args.count > 1 {
    musicDir = URL(fileURLWithPath: args[1])
} else {
    musicDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Music")
}

print("")
print("  PureVibes Cache Pipeline — Performance Monitor")
print("  ===============================================")
print("  Thresholds: RSS > \(Int(memoryThresholdMB))MB = WARNING, " +
      "CPU phase > \(Int(cpuSpikeThresholdMs))ms = WARNING")
print("")

// Phase 1: Enumerate
var s = ResourceSnapshot.now()
print("Phase 1: Enumerating audio files...")
print("  Directory: \(musicDir.path)")
let audioURLs = enumerateAudioFiles(in: musicDir)
var e = ResourceSnapshot.now()
measurements.append(PhaseMeasurement(name: "1. Enumerate", start: s, end: e))
print("  Found \(audioURLs.count) files | RSS: \(String(format: "%.1f", e.rssMB))MB | " +
      "CPU: \(String(format: "%.1f", e.totalCpuMs - s.totalCpuMs))ms")
print("")

if audioURLs.isEmpty {
    print("  No audio files found.")
    print("  Usage: swift scripts/simulate_cache_pipeline.swift /path/to/music")
    exit(0)
}

// Phase 2: Metadata-only
s = ResourceSnapshot.now()
print("Phase 2: Loading metadata-only (NO artwork)...")
let tracks = loadMetadataOnly(from: audioURLs)
e = ResourceSnapshot.now()
measurements.append(PhaseMeasurement(name: "2. Metadata", start: s, end: e))
print("  \(tracks.count) tracks | RSS: \(String(format: "%.1f", e.rssMB))MB | " +
      "CPU: \(String(format: "%.1f", e.totalCpuMs - s.totalCpuMs))ms")
print("")

// Phase 3: Group
s = ResourceSnapshot.now()
print("Phase 3: Grouping into albums...")
var albums = groupIntoAlbums(tracks)
e = ResourceSnapshot.now()
measurements.append(PhaseMeasurement(name: "3. Grouping", start: s, end: e))
let avg = Double(tracks.count) / max(Double(albums.count), 1.0)
print("  \(albums.count) albums (\(String(format: "%.1f", avg)) tracks/album) | " +
      "RSS: \(String(format: "%.1f", e.rssMB))MB | " +
      "CPU: \(String(format: "%.1f", e.totalCpuMs - s.totalCpuMs))ms")
print("")

// Phase 4: Artwork
s = ResourceSnapshot.now()
print("Phase 4: Per-album artwork extraction...")
extractArtworkPerAlbum(&albums)
e = ResourceSnapshot.now()
measurements.append(PhaseMeasurement(name: "4. Artwork", start: s, end: e))
let withArt = albums.filter { $0.hasArtwork }.count
print("  \(withArt)/\(albums.count) with artwork | " +
      "\(albums.count) extractions vs \(tracks.count) (old) | " +
      "RSS: \(String(format: "%.1f", e.rssMB))MB | " +
      "CPU: \(String(format: "%.1f", e.totalCpuMs - s.totalCpuMs))ms")
print("")

// Phase 5: Cache save
s = ResourceSnapshot.now()
print("Phase 5: Cache save simulation (batch=20)...")
simulateCacheSave(albums)
e = ResourceSnapshot.now()
measurements.append(PhaseMeasurement(name: "5. CacheSave", start: s, end: e))
print("  RSS: \(String(format: "%.1f", e.rssMB))MB | " +
      "CPU: \(String(format: "%.1f", e.totalCpuMs - s.totalCpuMs))ms")
print("")

// MARK: - Sustained Performance Report

print("  Performance Report")
print("  ==================")
print("")
print("  Phase            | Wall (s)  | CPU (ms)  | RSS Peak (MB)")
print("  -----------------+-----------+-----------+--------------")
for m in measurements {
    let wall = String(format: "%8.3f", m.wallSec)
    let cpu  = String(format: "%8.1f", m.cpuDeltaMs)
    let rss  = String(format: "%10.1f", m.rssPeakMB)
    print("  \(m.name.padding(toLength: 17, withPad: " ", startingAt: 0))| \(wall)  | \(cpu)  | \(rss)")
}
print("")

// Check for threshold violations
var warnings: [String] = []
let finalSnap = ResourceSnapshot.now()

if finalSnap.rssMB > memoryThresholdMB {
    warnings.append("RSS peak \(String(format: "%.0f", finalSnap.rssMB))MB exceeds \(Int(memoryThresholdMB))MB threshold")
}

for m in measurements {
    if m.cpuDeltaMs > cpuSpikeThresholdMs {
        warnings.append("\(m.name): CPU spike \(String(format: "%.0f", m.cpuDeltaMs))ms exceeds \(Int(cpuSpikeThresholdMs))ms threshold")
    }
}

// Check batch uniformity — flag any batch that took >3x the average
if batchSnapshots.count >= 2 {
    var batchCpuDeltas: [Double] = []
    var prev = measurements.first(where: { $0.name.contains("CacheSave") })?.start ?? ResourceSnapshot.now()
    for (_, snap) in batchSnapshots {
        batchCpuDeltas.append(snap.totalCpuMs - prev.totalCpuMs)
        prev = snap
    }
    let avgBatchCpu = batchCpuDeltas.reduce(0, +) / Double(batchCpuDeltas.count)
    for (i, delta) in batchCpuDeltas.enumerated() {
        if avgBatchCpu > 0 && delta > avgBatchCpu * 3.0 {
            warnings.append("Batch \(i + 1): CPU \(String(format: "%.0f", delta))ms is \(String(format: "%.1f", delta / avgBatchCpu))x the average — potential hotspot")
        }
    }
}

if warnings.isEmpty {
    print("  RESULT: PASS — No extreme spikes detected")
    print("  All phases within thresholds.")
} else {
    print("  RESULT: WARNING — \(warnings.count) issue(s) detected")
    for (i, w) in warnings.enumerated() {
        print("  \(i + 1). \(w)")
    }
}
print("")
