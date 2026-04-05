import Foundation
import Combine
import AVFoundation
import MediaPlayer
import SwiftUI

@MainActor
class MusicPlayer: ObservableObject {

    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var duration: TimeInterval = 0
    @Published var currentTrack: Track?
    @Published var queue: [QueueItem] = []
    @Published var currentIndex: Int = 0
    @Published var favorites: Set<UUID> = []
    @Published var loopMode: LoopMode = .off
    @Published var isShuffled = false
    @Published var isAlbumContext = false
    @Published var isLoadingLibrary = false
    @Published var loadedTrackCount = 0
    @Published var totalTrackCount = 0
    
    var prefs: UserPreferences
    
    func toggleFavorite(track: Track) {
        if favorites.contains(track.id) {
            favorites.remove(track.id)
            PersistenceService.shared.removeFavorite(trackURL: track.url.absoluteString)
        } else {
            favorites.insert(track.id)
            PersistenceService.shared.saveFavorite(trackURL: track.url.absoluteString)
        }
    }
    
    func isFavorite(_ track: Track) -> Bool {
        return favorites.contains(track.id)
    }
    
    @Published var albums: [Album] = [] {
        didSet {
            rebuildDerivedState()
        }
    }

    // MARK: - Cached Derived State (Issue 4: avoid recomputing on every access)

    /// Cached flattened tracks — rebuilt when albums changes.
    @Published private(set) var cachedAllTracks: [Track] = []

    /// Cached sorted albums — rebuilt when albums changes.
    @Published private(set) var cachedSortedAlbums: [Album] = []

    /// Track ID → Album ID index for O(1) lookup.
    private var trackToAlbumID: [UUID: UUID] = [:]

    /// Album ID → Album index for O(1) lookup.
    private var albumByID: [UUID: Album] = [:]

    /// Derived from albums — uses cached version.
    var allTracks: [Track] { cachedAllTracks }

    /// Performance-aware animation resolution
    var effectivePerformanceMode: PerformanceMode {
        PerformanceMode.determine(songCount: cachedAllTracks.count)
    }
    var effectiveTiltEnabled: Bool {
        prefs.tiltEnabled
    }
    var effectiveAnimationsEnabled: Bool {
        prefs.animationsEnabled
    }
    var effectiveBlurEnabled: Bool {
        prefs.blurEnabled
    }
    
    /// Sorted albums — uses cached version.
    var sortedAlbums: [Album] { cachedSortedAlbums }

    /// Rebuild all derived state when albums change.
    private func rebuildDerivedState() {
        cachedAllTracks = albums.flatMap { $0.tracks }
        cachedSortedAlbums = albums.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        // Rebuild track → album index
        trackToAlbumID.removeAll(keepingCapacity: true)
        albumByID.removeAll(keepingCapacity: true)
        for album in albums {
            albumByID[album.id] = album
            for track in album.tracks {
                trackToAlbumID[track.id] = album.id
            }
        }
    }

    /// Looks up artwork for the current track via ArtworkCache (keyed by album ID).
    /// Uses the O(1) track-to-album index instead of scanning all albums.
    func artworkForCurrentTrack() -> NSImage? {
        guard let track = currentTrack else { return nil }
        if let albumID = trackToAlbumID[track.id] {
            return ArtworkCache.shared.artwork(forAlbumID: albumID)
        }
        return nil
    }

    /// Looks up the album for the current track using O(1) index.
    func albumForCurrentTrack() -> Album? {
        guard let track = currentTrack else { return nil }
        if let albumID = trackToAlbumID[track.id] {
            return albumByID[albumID]
        }
        return nil
    }

    @Published var currentWaveform: [CGFloat] = Array(repeating: 0.3, count: 60)
    private var originalQueue: [QueueItem] = []
    var isScrubbing = false
    private var player: AVAudioPlayer?
    private var timer: Timer?
    
    deinit {
        timer?.invalidate()
        player?.stop()
    }
    private let playerDelegate = PlayerDelegate()
    
    init(prefs: UserPreferences) {
        self.prefs = prefs
        playerDelegate.onFinish = { [weak self] in Task { @MainActor in self?.handleTrackFinished() } }
        setupRemoteCommands()
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
            // Use ArtworkCache for artwork — no model-held NSImage
            if let artwork = artworkForCurrentTrack() {
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
                let currentItem = queue.first(where: { $0.track.id == current.id })
                let rest = queue.filter { $0.track.id != current.id }.shuffled()
                if let c = currentItem {
                    queue = [c] + rest
                    currentIndex = 0
                } else {
                    queue = rest
                    currentIndex = 0
                }
            }
            else { queue.shuffle(); currentIndex = 0 }
        } else { 
            if let current = currentTrack { 
                queue = originalQueue; 
                if let idx = queue.firstIndex(where: { $0.track.id == current.id }) { currentIndex = idx } 
            } else { 
                queue = originalQueue; currentIndex = 0 
            } 
        }
    }
    func playAlbum(_ album: Album, startingAt track: Track? = nil) {
        queue = album.tracks.map { QueueItem(track: $0) }
        originalQueue = queue; isShuffled = false
        isAlbumContext = true
        
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
            
            Task { [weak self] in
                if let cached = await PersistenceService.shared.loadCachedWaveform(trackURL: track.url.absoluteString) {
                    await MainActor.run { self?.currentWaveform = cached }
                } else {
                    // Use chunked WaveformExtractor instead of full-file allocation
                    let waveform = await WaveformExtractor.extract(from: track.url)
                    await MainActor.run { 
                        self?.currentWaveform = waveform 
                    }
                    let urlString = track.url.absoluteString
                    Task.detached(priority: .utility) {
                        await PersistenceService.shared.cacheWaveform(trackURL: urlString, data: waveform)
                    }
                }
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

    /// Issue 4: Reduced timer from 10 Hz (1/10) to 4 Hz (1/4).
    /// 4 Hz is more than sufficient for smooth scrubber/waveform progress display
    /// and reduces broad UI invalidation by 60%.
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/4.0, repeats: true) { [weak self] _ in
            guard let self = self, let player = self.player else { return }
            if !self.isScrubbing { self.currentTime = player.currentTime }
        }
    }

    private func handleTrackFinished() { if canGoNext || loopMode == .single || loopMode == .queue { playNext() } else { isPlaying = false; timer?.invalidate() } }
    
    func moveQueueItems(from source: IndexSet, to destination: Int) { 
        queue.move(fromOffsets: source, toOffset: destination); 
        if let current = currentTrack, let newIndex = queue.firstIndex(where: { $0.track.id == current.id }) { 
            currentIndex = newIndex 
        } 
    }
    func removeQueueItem(id: UUID) { 
        if let index = queue.firstIndex(where: { $0.id == id }) { 
            queue.remove(at: index); 
            if index < currentIndex { currentIndex -= 1 } 
            else if index == currentIndex { 
                if !queue.isEmpty { loadTrack(queue[max(0, currentIndex)].track) }
                else { currentTrack = nil; isPlaying = false } 
            } 
        } 
    }
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
        let _ = queue[index]; 
        queue.remove(at: index); 
        if index < currentIndex { currentIndex -= 1 } 
        else if index == currentIndex { 
            if !queue.isEmpty { loadTrack(queue[max(0, currentIndex)].track) } 
            else { currentTrack = nil; isPlaying = false } 
        } 
    }
    func clearQueue() { queue.removeAll(); originalQueue.removeAll(); currentIndex = 0; player?.stop(); currentTrack = nil; isPlaying = false }

}
