import SwiftUI
import Combine
import AVFoundation


// MARK: - Support Types

enum LoopMode {
    case off, single, queue
}

class PlayerDelegate: NSObject, AVAudioPlayerDelegate {
    var onFinish: () -> Void = {}
    var onDecodeError: (Error?) -> Void = { _ in }
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { if flag { onFinish() } }
    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { onDecodeError(error) }
}

struct QueueItem: Identifiable, Hashable {
    let id = UUID()
    let track: Track
}

// MARK: - Defaults & Preferences

enum DefaultsKey {
    static let libraryBookmarks   = "pv_libraryBookmarks"
    static let tiltEnabled        = "pv_tiltEnabled"
    static let animationsEnabled  = "pv_animationsEnabled"
    static let blurEnabled        = "pv_blurEnabled"
    static let startupView        = "pv_startupView"
    static let lastUsedView       = "pv_lastUsedView"
    static let hasLaunchedBefore  = "pv_hasLaunchedBefore"
    static let lastPlaybackPosition = "pv_lastPlaybackPosition"
    static let lastTrackURL       = "pv_lastTrackURL"
}

enum StartupViewPreference: String, CaseIterable, Identifiable {
    case carousel = "Carousel"
    case grid = "Grid"
    case lastUsed = "Last Used"
    var id: String { rawValue }
}

@MainActor
class UserPreferences: ObservableObject {
    @AppStorage(DefaultsKey.tiltEnabled)        var tiltEnabled        = true
    @AppStorage(DefaultsKey.animationsEnabled)   var animationsEnabled  = true
    @AppStorage(DefaultsKey.blurEnabled)         var blurEnabled        = true
    @AppStorage(DefaultsKey.startupView)        var startupViewRaw     = StartupViewPreference.grid.rawValue
    @AppStorage(DefaultsKey.lastUsedView)       var lastUsedView       = "grid"

    var startupView: StartupViewPreference {
        get { StartupViewPreference(rawValue: startupViewRaw) ?? .lastUsed }
        set { startupViewRaw = newValue.rawValue }
    }
}

enum PerformanceMode: String, CaseIterable {
    case full       // ≤ 200 songs
    case balanced   // 201–500 songs
    case lite       // > 500 songs

    static func determine(songCount: Int) -> PerformanceMode {
        if songCount <= 200 { return .full }
        if songCount <= 500 { return .balanced }
        return .lite
    }
}
