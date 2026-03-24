//
//  ContentView.swift
//  MusicPlayer
//
//  Created by Srikar on 28/01/2026.
//

import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

import CoreMedia
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.purevibes.app", category: "ContentView")


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
                window.isMovableByWindowBackground = false
                window.isMovable = true
                window.setFrameAutosaveName("PureVibesMainWindow")
                window.minSize = NSSize(width: 800, height: 600)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
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
    private func restart() { withAnimation(.none) { offset = 0 }; Task { @MainActor in try? await Task.sleep(for: .milliseconds(50)); startAnimation() } }
}


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
                    // Use ArtworkCache via album lookup for queue popup artwork
                    if let album = player.albumForCurrentTrack(), let artwork = ArtworkCache.shared.thumbnail(forAlbumID: album.id, maxSize: 44) ?? album.artwork?.thumbnail() {
                        Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 44).cornerRadius(8)
                    } else if let artwork = current.artwork { Image(nsImage: artwork.thumbnail()).resizable().aspectRatio(contentMode: .fill).frame(width: 44, height: 44).cornerRadius(8) }
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
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
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
    @State private var cachedFavoriteTracks: [Track] = []
    
    enum SortOption: String, CaseIterable {
        case title = "Song Name"
        case album = "Album"
        case artist = "Artist"
        case trackNumber = "Track Number" // Fallback to title if disparate albums
    }
    
    private func computedFavoriteTracks() -> [Track] {
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
                    Text("\(cachedFavoriteTracks.count) Songs")
                        .font(.system(size: 18, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                                Button(action: {
                                    // Convert tracks to QueueItems for playback
                                    player.queue = cachedFavoriteTracks.map { QueueItem(track: $0) }
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
                                                                        ForEach(cachedFavoriteTracks) { track in
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
        .onAppear { cachedFavoriteTracks = computedFavoriteTracks() }
        .onChange(of: player.favorites) { _ in cachedFavoriteTracks = computedFavoriteTracks() }
        .onChange(of: sortOption) { _ in cachedFavoriteTracks = computedFavoriteTracks() }
        }
    }



struct MiniPlayerPill: View {
    @ObservedObject var player: MusicPlayer
    let openDirectories: () -> Void
    @Binding var showFavorites: Bool
    @Binding var showQueuePopup: Bool
    @State private var rotation: Double = 0
    @State private var lastSpinDate: Date = .now
    @State private var localDragPct: Double? = nil
    @State private var lastDragPct: Double = 0 // For calculating scrub direction
    // Waveform States
    // Removed local amplitudes state, using player.currentWaveform directly
    @State private var loadProgress: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Main Pill
            HStack(spacing: 0) {
                // 1. Album Art Spinner — uses ArtworkCache thumbnail for efficiency
                ZStack { 
                    if let album = player.albumForCurrentTrack(),
                       let artwork = ArtworkCache.shared.thumbnail(forAlbumID: album.id, maxSize: 46) ?? album.artwork?.thumbnail() {
                        TimelineView(.animation(minimumInterval: 1.0/30.0, paused: !player.isPlaying || player.isScrubbing)) { context in
                            Image(nsImage: artwork).resizable().aspectRatio(contentMode: .fill).frame(width: 46, height: 46).clipShape(Circle())
                                .rotationEffect(.degrees(rotation))
                                .onChange(of: context.date) { newDate in
                                    let dt = newDate.timeIntervalSince(lastSpinDate)
                                    lastSpinDate = newDate
                                    // 45 degrees/sec = one full rotation every 8 seconds
                                    if dt > 0 && dt < 1 { rotation += 45.0 * dt }
                                }
                        }
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
                                .animation(.linear(duration: 0.05), value: handleX)
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
                                .animation(.linear(duration: 0.05), value: handleX)
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
                                    Task { @MainActor in
                                        try? await Task.sleep(for: .milliseconds(100))
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
                        let isFav = player.currentTrack.map { player.isFavorite($0) } == true
                        Image(systemName: isFav ? "star.fill" : "star")
                            .font(.system(size: 14))
                            .foregroundColor(isFav ? .accentColor : .secondary)
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
    @Binding var showFavoritesList: Bool
    var albumCount: Int
    
    var body: some View {
        HStack(spacing: 16) {
            // 1. View Toggle
            Button(action: { 
                withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { 
                    isGridView.toggle()
                } 
            }) {
                Image(systemName: isGridView || albumCount > 150 ? "rectangle.grid.1x2" : "square.grid.2x2")
                    .font(.system(size: 16))
                    .foregroundColor(albumCount > 150 ? .gray.opacity(0.3) : .white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .disabled(albumCount > 150)
            .help(albumCount > 150 ? "Carousel disabled for libraries over 150 albums" : "Toggle View")
            
            // 2. Queue Toggle
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showQueuePopup.toggle() } }) {
                Image(systemName: "list.bullet").font(.system(size: 16)).foregroundColor(showQueuePopup ? .accentColor : .secondary)
            }
            .buttonStyle(.plain)
            
            // 3. Favorites List Toggle
            Button(action: { withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showFavorites.toggle() } }) {
                Image(systemName: showFavorites ? "star.square.fill" : "star.square").font(.system(size: 16)).foregroundColor(showFavorites ? .accentColor : .secondary)
            }.buttonStyle(.plain)
            
            // 4. Divider
            Divider().frame(height: 16).background(Color.white.opacity(0.2))
            
            // 5. Open Directory
            Button(action: openDirectories) {
                Image(systemName: "folder.badge.plus").font(.system(size: 16)).foregroundColor(.secondary)
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

struct AlbumBrowserView: View {
    let albums: [Album]
    @ObservedObject var player: MusicPlayer
    @Binding var isGridView: Bool
    @Binding var currentScrollID: UUID?
    var namespace: Namespace.ID
    var selectedAlbumID: UUID?
    let onSelect: (Album) -> Void
    
    @State private var searchText = ""
    
    var filteredAlbums: [Album] {
        if searchText.isEmpty { return albums }
        return albums.filter { $0.title.localizedCaseInsensitiveContains(searchText) || $0.artist.localizedCaseInsensitiveContains(searchText) }
    }
    
    // Alphabet grouping
    var alphabetLetters: [String] {
        let letters = Set(filteredAlbums.compactMap { $0.title.first?.uppercased() }).sorted()
        return letters
    }

    var body: some View {
        VStack(spacing: 0) {
            // Search Bar
            HStack {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Search albums or artists...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.custom("Baskerville", size: 16))
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }.buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 40)
            .padding(.top, 8)
            
            ZStack(alignment: .bottom) {
                ScrollViewReader { proxy in
                    if isGridView || albums.count > 150 {
                        AlbumGridView(albums: filteredAlbums, player: player, onSelect: onSelect)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.9)), removal: .opacity.combined(with: .scale(scale: 1.1))))
                    } else {
                        AlbumCarouselViewInternal(albums: filteredAlbums, player: player, currentScrollID: $currentScrollID, namespace: namespace, selectedAlbumID: selectedAlbumID, onSelect: onSelect)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .padding(.bottom, 60)
                            .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 1.1)), removal: .opacity.combined(with: .scale(scale: 0.9))))
                    }
                    
                    // Alphabet Scrubber
                    if !filteredAlbums.isEmpty && searchText.isEmpty {
                        HStack(spacing: 2) {
                            ForEach(alphabetLetters, id: \.self) { letter in
                                Text(letter)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white.opacity(0.8))
                                    .padding(.vertical, 4)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if let target = filteredAlbums.first(where: { $0.title.uppercased().hasPrefix(letter) }) {
                                            withAnimation {
                                                proxy.scrollTo(target.id, anchor: isGridView ? .top : .center)
                                            }
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(Material.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Color.white.opacity(0.2), lineWidth: 1))
                        .padding(.bottom, isGridView ? 60 : 120)
                        .zIndex(10)
                    }
                }
            }
        }
    }
}

struct AlbumCarouselViewInternal: View {
    let albums: [Album]
    @ObservedObject var player: MusicPlayer
    @Binding var currentScrollID: UUID?
    var namespace: Namespace.ID
    var selectedAlbumID: UUID?
    let onSelect: (Album) -> Void
    
    // Support throttle
    @State private var pendingScrollID: UUID? = nil
    @State private var scrollTask: Task<Void, Never>? = nil

    var body: some View {
        GeometryReader { fullProxy in
            let availableWidth = fullProxy.size.width
            let availableHeight = fullProxy.size.height
            
            let bottomReserve: CGFloat = 120
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
                                    .scrollTransition(.interactive, axis: .horizontal) { content, phase in 
                                        let rotation = player.prefs.animationsEnabled ? phase.value * -30 : 0
                                        return content.scaleEffect(phase.isIdentity ? 1.1 : 0.6).opacity(phase.isIdentity ? 1.0 : 0.2).brightness(phase.isIdentity ? 0.05 : -0.5).rotation3DEffect(.degrees(rotation), axis: (x: 0, y: 1, z: 0), perspective: 0.5) 
                                    }
                                    .onTapGesture { if currentScrollID == album.id { withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { onSelect(album) } } else { withAnimation(.spring()) { currentScrollID = album.id } } }
                                    .id(album.id)
                            }
                        }
                        .scrollTargetLayout()
                        .padding(.top, 100)
                        .padding(.bottom, 80)
                    }
                    .coordinateSpace(name: "carousel")
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
                        if pendingScrollID != closest.key {
                            pendingScrollID = closest.key
                            scrollTask?.cancel()
                            scrollTask = Task { @MainActor in
                                do {
                                    try await Task.sleep(nanoseconds: 50_000_000)
                                    if !Task.isCancelled && currentScrollID != pendingScrollID {
                                        currentScrollID = pendingScrollID
                                    }
                                } catch {}
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
                    .onAppear {
                        ArtworkCache.shared.ensureDominantColor(forAlbumID: album.id)
                    }
                    .onChange(of: currentScrollID) { newID in
                        if let newID = newID {
                            ArtworkCache.shared.ensureDominantColor(forAlbumID: newID)
                        }
                    }
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
            .padding(.top, 30) // Extra clearance for tilt/scale overshoot
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
                Group {
                    // Read artwork from ArtworkCache first, fall back to album.artwork
                    if let artwork = ArtworkCache.shared.artwork(forAlbumID: album.id) ?? album.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    } else {
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
                guard player.effectiveTiltEnabled else {
                    isHovering = false; tiltX = 0; tiltY = 0
                    return
                }
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

        .contextMenu {
            Button(action: { if let first = album.tracks.first { player.playNext(first) } }) { Label("Play Next", systemImage: "text.line.first.and.arrowtriangle.forward") }
            Button(action: { album.tracks.forEach { player.addToQueue($0) } }) { Label("Add to Queue", systemImage: "text.badge.plus") }
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
                        withAnimation(.easeInOut(duration: Double.random(in: 3.0...5.0)).repeatForever(autoreverses: true)) {
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
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 15.0)) { context in
            let interval: Double = context.date.timeIntervalSinceReferenceDate
            let remainder: Double = interval.truncatingRemainder(dividingBy: 30.0)
            let phase: CGFloat = CGFloat(remainder) * (.pi * 2.0 / 30.0)
            Canvas { ctx, size in
                let w: CGFloat = size.width
                let h: CGFloat = size.height
                let baseRadius: CGFloat = min(w, h) * 0.4
                let phaseDouble: Double = Double(phase)
                var path = Path()
                for i in 0..<360 {
                    let iDouble: Double = Double(i)
                    let angle: Double = iDouble * .pi / 180.0
                    let wave1: CGFloat = CGFloat(sin(iDouble * 0.05 + phaseDouble)) * 20.0
                    let wave2: CGFloat = CGFloat(cos(iDouble * 0.1 + phaseDouble * 0.5)) * 20.0
                    let r: CGFloat = baseRadius + wave1 + wave2
                    let x: CGFloat = w * 0.5 + CGFloat(cos(angle)) * r
                    let y: CGFloat = h * 0.5 + CGFloat(sin(angle)) * r
                    if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                    else { path.addLine(to: CGPoint(x: x, y: y)) }
                }
                path.closeSubpath()
                ctx.fill(path, with: .color(Color.accentColor.opacity(0.3)))
            }
        }
        .blur(radius: 30)
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
        .drawingGroup() // Rasterize to avoid per-frame Canvas redraws
        .allowsHitTesting(false)
    }
}

// MARK: - Main ContentView

struct ContentView: View {
    @ObservedObject var player: MusicPlayer
    @ObservedObject var prefs: UserPreferences
    @State private var focusedAlbumID: UUID?
    @State private var selectedAlbum: Album? = nil
    @State private var showFavorites = false // State for favorites view
    @State private var isGridView = true // Grid is default; carousel is opt-in
    @State private var showQueuePopup = false // State for queue popup
    @State private var hasOpened = false
    @State private var mouseLocation: CGPoint = CGPoint(x: -200, y: -200) // State for grid
    @Namespace private var albumNamespace
    var body: some View {
        ZStack {
            WindowAccessor()
            
            // Background Theme Logic
            Color.black.ignoresSafeArea() // OLED Base
            
            if player.effectiveBlurEnabled, let artwork = currentArtwork { 
                GeometryReader { geo in 
                    Image(nsImage: artwork.thumbnail(maxSize: 100))
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: 60)
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

                // Main Content Area
                GeometryReader { contentGeo in
                    ZStack(alignment: .center) { // Changed to center
                        VStack(spacing: 0) {
                            if player.albums.isEmpty && !player.isLoadingLibrary { 
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
                                }
                                .frame(maxWidth: .infinity)
                                Spacer()
                            } else if player.isLoadingLibrary && player.albums.isEmpty {
                                // Loading indicator while library is being loaded
                                Spacer()
                                VStack(spacing: 20) {
                                    CustomLiquidSpinner()
                                    Text("Loading Library")
                                        .font(.custom("Baskerville", size: 24))
                                        .foregroundColor(.white)
                                    if player.totalTrackCount > 0 {
                                        Text("\(player.loadedTrackCount) / \(player.totalTrackCount) tracks")
                                            .font(.system(size: 14, design: .monospaced))
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                Spacer()
                            }
                            else {
                                AlbumBrowserView(
                                    albums: player.sortedAlbums,
                                    player: player,
                                    isGridView: $isGridView,
                                    currentScrollID: $focusedAlbumID,
                                    namespace: albumNamespace,
                                    selectedAlbumID: selectedAlbum?.id
                                ) { album in
                                    withAnimation(.interpolatingSpring(stiffness: 120, damping: 20)) { selectedAlbum = album }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(.top, 20) // Ensure tilt/scale never clips at top edge
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
                                isGridView: Binding(
                                    get: { isGridView },
                                    set: { newValue in
                                        isGridView = newValue
                                        prefs.lastUsedView = newValue ? "grid" : "carousel"
                                    }
                                ),
                                showFavoritesList: $showFavorites,
                                albumCount: player.albums.count
                            )
                            .scaleEffect(pillScale)
                            .padding(.trailing, 40)
                        }
                    }
                    .padding(.bottom, 25)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .zIndex(1)
            .animation(.easeOut(duration: 0.8), value: player.albums.isEmpty) // Animate layout changes
        }
        .frame(minWidth: 1000, minHeight: 700)
        .onAppear {
            withAnimation(.easeOut(duration: 1.2)) { hasOpened = true }
            // Apply startup view preference
            switch prefs.startupView {
            case .carousel: isGridView = false
            case .grid:     isGridView = true
            case .lastUsed: isGridView = (prefs.lastUsedView == "grid")
            }
            loadCachedLibrary()
        }
        .onChange(of: focusedAlbumID) { _ in 
            NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
        }
        // Menu bar command handlers
        .onReceive(NotificationCenter.default.publisher(for: .menuOpenDirectory)) { _ in openDirectories() }
        .onReceive(NotificationCenter.default.publisher(for: .menuPlayPause)) { _ in
            if player.isPlaying { player.pause() } else { player.play() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuNextTrack)) { _ in player.playNext() }
        .onReceive(NotificationCenter.default.publisher(for: .menuPrevTrack)) { _ in player.playPrevious() }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleLoop)) { _ in
            switch player.loopMode {
            case .off: player.loopMode = .single
            case .single: player.loopMode = .queue
            case .queue: player.loopMode = .off
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleShuffle)) { _ in player.toggleShuffle() }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleGrid)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                isGridView.toggle()
                prefs.lastUsedView = isGridView ? "grid" : "carousel"
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuToggleFavorites)) { _ in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) { showFavorites.toggle() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .menuPurgeCache)) { _ in
            PersistenceService.shared.purgeAllCache()
        }
    }
    private var pillScale: CGFloat { NSApp.keyWindow?.frame.height ?? 700 < 600 ? 0.8 : 1.0 }
    private var currentArtwork: NSImage? {
        // Read from ArtworkCache first, then fall back to album.artwork
        if let focusedID = focusedAlbumID, let album = player.albums.first(where: { $0.id == focusedID }) {
            return ArtworkCache.shared.artwork(forAlbumID: album.id) ?? album.artwork
        }
        return player.artworkForCurrentTrack()
    }
    private func openDirectories() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            let selectedURLs = panel.urls
            PersistenceService.shared.activeBookmarks = selectedURLs
            for url in selectedURLs {
                PersistenceService.shared.saveBookmark(for: url)
                _ = url.startAccessingSecurityScopedResource()
            }
            loadAlbums(from: selectedURLs)
        }
    }
    private func loadCachedLibrary() {
        Task {
            // Re-establish sandbox access for all saved bookmark directories.
            // This MUST happen before any file reads (playback, artwork, etc.)
            // because the app is sandboxed with user-selected.read-only entitlement.
            // Without startAccessingSecurityScopedResource(), AVAudioPlayer silently
            // fails on every cached track URL.
            let bookmarkURLs = PersistenceService.shared.loadBookmarks()
            PersistenceService.shared.activeBookmarks = bookmarkURLs
            for url in bookmarkURLs {
                _ = url.startAccessingSecurityScopedResource()
            }

            if let cachedAlbums = PersistenceService.shared.loadCachedAlbums() {
                var allTracks: [Track] = []
                for album in cachedAlbums {
                    allTracks.append(contentsOf: album.tracks)
                    if let art = album.artwork {
                        ArtworkCache.shared.setArtwork(art, forAlbumID: album.id)
                    }
                }

                await MainActor.run {
                    player.allTracks = allTracks
                    player.albums = cachedAlbums
                    player.isLoadingLibrary = false
                    focusedAlbumID = cachedAlbums.first?.id
                    if allTracks.count > 500 { ArtworkCache.shared.trimToHalf() }
                }
            } else {
                // No valid cache — fall back to a full re-scan using saved bookmarks.
                // This handles the case where cache is empty/expired but bookmarks exist.
                if !bookmarkURLs.isEmpty {
                    await MainActor.run {
                        loadAlbums(from: bookmarkURLs)
                    }
                } else {
                    await MainActor.run {
                        player.isLoadingLibrary = false
                    }
                }
            }
        }
    }

    private func loadAlbums(from urls: [URL]) {
        Task {
            player.isLoadingLibrary = true
            player.loadedTrackCount = 0

            // 2. Enumerate audio files on a background thread
            let audioURLs: [URL] = await Task.detached(priority: .userInitiated) {
                urls.flatMap { baseURL -> [URL] in
                    guard let en = FileManager.default.enumerator(
                        at: baseURL,
                        includingPropertiesForKeys: [.contentTypeKey]
                    ) else { return [] }
                    return (en.allObjects as? [URL] ?? []).filter { file in
                        (try? file.resourceValues(forKeys: [.contentTypeKey]).contentType)?.conforms(to: .audio) == true
                    }
                }
            }.value

            player.totalTrackCount = audioURLs.count
            
            // Phase 1: Create stubs
            let stubs = audioURLs.map { TrackStub(url: $0) }
            await MainActor.run { player.allStubs = stubs }
            
            // Phase 2/3: Resolve stubs with cache or full load (max 4 concurrent)
            let maxConcurrency = 4
            var allTracks: [Track] = []
            allTracks.reserveCapacity(audioURLs.count)

            await withTaskGroup(of: Track?.self) { group in
                var submitted = 0

                while submitted < min(maxConcurrency, stubs.count) {
                    let stub = stubs[submitted]
                    group.addTask { await self.player.resolve(stub) }
                    submitted += 1
                }

                for await track in group {
                    if let t = track { allTracks.append(t) }

                    let loaded = allTracks.count
                    if loaded % 50 == 0 || loaded == stubs.count {
                        await MainActor.run { player.loadedTrackCount = loaded }
                    }

                    if submitted < stubs.count {
                        let stub = stubs[submitted]
                        group.addTask { await self.player.resolve(stub) }
                        submitted += 1
                    }
                }
            }

            // Group into albums
            var albums = groupTracksIntoAlbums(allTracks)

            // Populate ArtworkCache
            for album in albums {
                if let art = album.artwork {
                    ArtworkCache.shared.setArtwork(art, forAlbumID: album.id)
                }
            }

            // Nil out per-track artwork to reclaim memory safely matching Album assert
            for i in allTracks.indices {
                allTracks[i].artwork = nil
            }
            for albumIdx in albums.indices {
                var updatedTracks = albums[albumIdx].tracks
                for trackIdx in updatedTracks.indices {
                    updatedTracks[trackIdx].artwork = nil
                }
                albums[albumIdx].tracks = updatedTracks
            }

            // Async save to cache
            PersistenceService.shared.saveAlbums(albums)

            // Update UI on main actor
            await MainActor.run {
                player.allTracks = allTracks
                player.albums = albums
                player.isLoadingLibrary = false
                focusedAlbumID = albums.first?.id
                if allTracks.count > 500 { ArtworkCache.shared.trimToHalf() }
            }
        }
    }

    private func groupTracksIntoAlbums(_ tracks: [Track]) -> [Album] {
        let rawGroups = Dictionary(grouping: tracks) { $0.album }
        var albums: [Album] = []

        for (albumName, albumTracks) in rawGroups {
            let explicitAlbumArtists = Set(albumTracks.compactMap { $0.albumArtist })
            var finalArtist: String
            if let singleArtist = explicitAlbumArtists.first, explicitAlbumArtists.count == 1 {
                finalArtist = singleArtist
            } else {
                let trackArtists = Set(albumTracks.map { $0.artist })
                if trackArtists.count == 1, let first = trackArtists.first {
                    finalArtist = first
                } else {
                    let counts = albumTracks.map { $0.artist }.reduce(into: [:]) { $0[$1, default: 0] += 1 }
                    finalArtist = counts.max(by: { $0.value < $1.value })?.key ?? "Various Artists"
                }
            }
            let sorted = albumTracks.sorted {
                let d1 = $0.discNumber ?? 1
                let d2 = $1.discNumber ?? 1
                if d1 != d2 { return d1 < d2 }
                return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
            }
            if let first = sorted.first {
                let artwork = first.artwork
                let cleanTracks = sorted.map { track -> Track in
                    var t = track
                    t.artwork = nil
                    return t
                }
                albums.append(Album(
                    title: albumName,
                    artist: finalArtist,
                    albumArtist: finalArtist,
                    artwork: artwork,
                    tracks: cleanTracks
                ))
            }
        }
        return albums.sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Full screen on launch removed as per request
    }
}

// MARK: - Notification Names for Menu Commands

extension NSNotification.Name {
    static let menuOpenDirectory  = NSNotification.Name("pv.menu.openDirectory")
    static let menuPlayPause      = NSNotification.Name("pv.menu.playPause")
    static let menuNextTrack      = NSNotification.Name("pv.menu.nextTrack")
    static let menuPrevTrack      = NSNotification.Name("pv.menu.prevTrack")
    static let menuToggleLoop     = NSNotification.Name("pv.menu.toggleLoop")
    static let menuToggleShuffle  = NSNotification.Name("pv.menu.toggleShuffle")
    static let menuToggleGrid     = NSNotification.Name("pv.menu.toggleGrid")
    static let menuToggleFavorites = NSNotification.Name("pv.menu.toggleFavorites")
    static let menuPurgeCache     = NSNotification.Name("pv.menu.purgeCache")
}

@main 
struct MusicPlayerApp: App { 
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var prefs: UserPreferences
    @StateObject private var player: MusicPlayer

    init() {
        let sharedPrefs = UserPreferences()
        _prefs  = StateObject(wrappedValue: sharedPrefs)
        _player = StateObject(wrappedValue: MusicPlayer(prefs: sharedPrefs))
    }

    var body: some Scene { 
        WindowGroup { 
            ContentView(player: player, prefs: prefs)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            // File Menu
            CommandGroup(replacing: .newItem) {
                Button("Open Music Folder…") {
                    NotificationCenter.default.post(name: .menuOpenDirectory, object: nil)
                }
                .keyboardShortcut("o")
            }

            // Playback Menu
            CommandMenu("Playback") {
                Button("Play / Pause") {
                    NotificationCenter.default.post(name: .menuPlayPause, object: nil)
                }
                .keyboardShortcut(.space, modifiers: [])

                Button("Next Track") {
                    NotificationCenter.default.post(name: .menuNextTrack, object: nil)
                }
                .keyboardShortcut(.rightArrow, modifiers: .command)

                Button("Previous Track") {
                    NotificationCenter.default.post(name: .menuPrevTrack, object: nil)
                }
                .keyboardShortcut(.leftArrow, modifiers: .command)

                Divider()

                Button("Toggle Loop") {
                    NotificationCenter.default.post(name: .menuToggleLoop, object: nil)
                }
                .keyboardShortcut("l", modifiers: .command)

                Button("Toggle Shuffle") {
                    NotificationCenter.default.post(name: .menuToggleShuffle, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
            }

            // View Menu
            CommandMenu("View") {
                Button("Toggle Grid / Carousel") {
                    NotificationCenter.default.post(name: .menuToggleGrid, object: nil)
                }
                .keyboardShortcut("g", modifiers: .command)

                Button("Toggle Favorites") {
                    NotificationCenter.default.post(name: .menuToggleFavorites, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command, .shift])

                Divider()

                Picker("Open With", selection: $prefs.startupViewRaw) {
                    ForEach(StartupViewPreference.allCases) { pref in
                        Text(pref.rawValue).tag(pref.rawValue)
                    }
                }
            }

            // Animations Menu
            CommandMenu("Animations") {
                Toggle("Cover Animations", isOn: $prefs.animationsEnabled)
                Toggle("3D Tilt on Hover", isOn: $prefs.tiltEnabled)
                Toggle("Background Blur", isOn: $prefs.blurEnabled)
            }

            // Library Menu
            CommandMenu("Library") {
                Button("Purge All Cache") {
                    NotificationCenter.default.post(name: .menuPurgeCache, object: nil)
                }
            }
        }
    } 
}
