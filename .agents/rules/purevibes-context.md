# PureVibes — Project Context for Claude Code

This file gives you full architectural context for PureVibes. Read it before making any changes.

---

## What This App Is

PureVibes is a native macOS music player for self-hosted libraries, built entirely in Swift and SwiftUI. No Electron, no web views. It targets macOS Sonoma (14.0+) and uses AVFoundation for audio playback and metadata parsing, CoreData for persistence, and MediaPlayer for Now Playing / media key integration.

The app is in active development. The current priority is stability and getting the project cleanly renamed from its original internal name (MusicApp) to PureVibes.

---

## File Map

```
PureVibes/
├── PureVibesApp.swift        ← @main entry point, also defines menu bar commands
├── ContentView.swift         ← Everything: library scan, carousel, grid, mini player, queue panel
├── MusicPlayer.swift         ← ObservableObject brain: playback, queue, shuffle, waveform, LRU cache
├── Track.swift               ← Struct for one song: metadata parsing, ADM detection, quality tiers
├── Album.swift               ← Struct grouping tracks: artwork lives HERE, not on tracks
├── SupportTypes.swift        ← Shared enums/classes: LoopMode, PlayerDelegate, DefaultsKey, UserPreferences, PerformanceMode
├── ArtworkCache.swift        ← Three-tier NSCache system for artwork (128MB full + 32MB thumbs + color dict)
├── PersistenceService.swift  ← CoreData stack (programmatic — no .xcdatamodeld file), bookmarks, waveform cache
├── MetadataViews.swift       ← Reusable badge/display components: MetadataBadge, AppleDigitalMasterBadge, TrackListRow
├── WelcomeView.swift         ← First-launch screen, NSOpenPanel folder selection
└── NSImage_Extensions.swift  ← dominantColor(), thumbnail(), averageBrightness(), contrastRatio() (ITU-R BT.709)
```

---

## Critical Architecture Rules

These are non-negotiable. Violating any of them will cause crashes or silent memory bugs.

### 1. Artwork lives on Album, never on Track (inside an Album)
`Album.swift` has a `#if DEBUG` assert that hard-crashes if any track inside an album has non-nil artwork. The correct flow is:

```swift
let artwork = tracks.first?.artwork       // save it
let cleanTracks = tracks.map { t -> Track in var t = t; t.artwork = nil; return t }
let album = Album(..., artwork: artwork, tracks: cleanTracks)
// Then: ArtworkCache.shared.setArtwork(artwork, forAlbumID: album.id)
```

This is enforced in `groupTracksIntoAlbums()` inside `ContentView.swift`.

### 2. CoreData model is programmatic — no .xcdatamodeld
`PersistenceService.buildModel()` defines all six entities in code:
- `CachedAlbum`, `CachedTrack`, `CachedFavorite`, `UserRating`, `SecurityScopedBookmark`, `QueueState`

Never add a `.xcdatamodeld` file. If you need a new entity or attribute, add it to `buildModel()`.

### 3. All UI updates must be on @MainActor
`MusicPlayer`, `ArtworkCache`, and `UserPreferences` are all `@MainActor`. Any background work that touches these must route back via `await MainActor.run { }` or `Task { @MainActor in }`.

### 4. ArtworkCache is the single source for images
The UI must never read `track.artwork` or `album.artwork` directly for display. Always use:
- `ArtworkCache.shared.artwork(forAlbumID:)` — full res
- `ArtworkCache.shared.thumbnail(forAlbumID:maxSize:)` — thumbnails
- `ArtworkCache.shared.dominantColor(forAlbumID:)` — background tinting

### 5. Never commit build artifacts
`build.log`, `*.log`, `DerivedData/`, `*.xcarchive` are all gitignored. Don't add them back.

---

## Key Subsystems

### Library Scan Pipeline (ContentView.swift)
1. User picks folder(s) via `NSOpenPanel` in `WelcomeView`
2. `scanDirectory()` recursively finds audio files, creates `TrackStub` array (fast — just URLs)
3. `TaskGroup` resolves stubs to full `Track` objects in parallel (calls `MusicPlayer.resolve()`)
4. `groupTracksIntoAlbums()` groups tracks by album name, strips artwork from tracks, creates `Album` objects
5. `ArtworkCache.shared.populate(from: albums)` loads all artwork into the cache
6. `PersistenceService.shared.saveAlbums(albums)` writes to CoreData for next-launch fast load

### Waveform Pipeline (MusicPlayer.swift)
1. `loadTrack()` is called when a track starts
2. Checks `PersistenceService.loadCachedWaveform()` first — if hit, loads instantly
3. On cache miss: `extractWaveform()` reads the full `AVAudioPCMBuffer`, divides into 60 chunks, computes RMS energy per chunk using a strided pass (every ~100th sample)
4. Result (60 CGFloat values 0–1) stored to CoreData via `PersistenceService.cacheWaveform()`
5. `currentWaveform` is a `@Published` array — UI reacts automatically

### Apple Digital Master Detection (Track.swift → extractiTunesMetadata)
Three independent signals — any one is sufficient:
- `flvr` atom with value `2` or string prefix `"2:"`
- Co-presence of `atID` (Apple Track ID) + `cnID` (Catalog Number)
- `ownr` ownership atom

### Adaptive Performance (SupportTypes.swift → PerformanceMode)
- ≤200 tracks → `.full` (all animations, tilt, blur enabled)
- 201–500 tracks → `.balanced`
- >500 tracks → `.lite` (reduced animations)

Checked via `MusicPlayer.effectivePerformanceMode`. UI reads `effectiveTiltEnabled`, `effectiveAnimationsEnabled`, `effectiveBlurEnabled`.

---

## Patterns Used Throughout

### ObservableObject + @Published (SwiftUI reactivity)
`MusicPlayer` and `UserPreferences` are `ObservableObject`. Any `@Published` property change automatically triggers UI redraws in all views observing that object. Don't manually call `objectWillChange.send()` unless you have a very specific reason.

### @AppStorage (UserDefaults binding)
`UserPreferences` uses `@AppStorage` for all persisted settings. The keys are namespaced with `pv_` prefix in `DefaultsKey`. Add new settings here, not with raw `UserDefaults.standard.set(...)` calls.

### Delegate Pattern (AVAudioPlayer)
`PlayerDelegate` in `SupportTypes.swift` is the `AVAudioPlayerDelegate`. It bridges AVFoundation callbacks into Swift closures. `onFinish` is wired in `MusicPlayer.init()` to call `handleTrackFinished()`.

### Security-Scoped Bookmarks
Folder access is persisted across launches via `SecurityScopedBookmark` CoreData entities. On launch, `PersistenceService.loadBookmarks()` resolves these and calls `url.startAccessingSecurityScopedResource()`. Always call `stopAccessingSecurityScopedResource()` when done with a URL.

---

## What's Currently Known Broken / In Progress

- The `#if DEBUG` artwork assertion was only recently caught by running a Debug build for the first time. The fix (stripping artwork inside `groupTracksIntoAlbums` before `Album` init) was just applied.
- The internal Xcode project was previously named `MusicApp`. The migration to `PureVibes` is fresh. If you see any `MusicApp` string references remaining, replace them with `PureVibes` or `com.purevibes.app`.

---

## What Not to Touch Without Discussion

- `buildModel()` in `PersistenceService` — adding/removing CoreData attributes without a migration strategy will corrupt existing stores
- `groupTracksIntoAlbums()` — the artwork stripping logic is load-bearing; the assert will catch mistakes immediately in debug
- The `NSCache` cost calculations in `ArtworkCache` — these are pixel-accurate (`width × height × 4`) and directly enforce the 128MB/32MB byte budgets

---

## Build & Run

1. Open `PureVibes.xcodeproj` in Xcode 15+
2. Select the `PureVibes` scheme, target your Mac
3. ⌘R to build and run
4. On first launch, select a folder containing music files (.m4a, .mp3, .flac, .wav, .ogg)

No external dependencies. No SPM packages. No CocoaPods. Pure Apple frameworks only:
`SwiftUI · AVFoundation · CoreData · MediaPlayer · AppKit · OSLog · CoreMedia · UniformTypeIdentifiers`
