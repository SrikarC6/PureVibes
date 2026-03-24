import SwiftUI

struct Album: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String 
    let albumArtist: String?
    let artwork: NSImage?
    var tracks: [Track] {
        didSet {
            #if DEBUG
            for track in tracks {
                assert(track.artwork == nil, "Artwork must not be duplicated in Track models inside an Album.")
            }
            #endif
        }
    }

    init(title: String, artist: String, albumArtist: String?, artwork: NSImage?, tracks: [Track]) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.artwork = artwork
        self.tracks = tracks
        #if DEBUG
        for track in tracks {
            assert(track.artwork == nil, "Artwork must not be duplicated in Track models inside an Album.")
        }
        #endif
    }

    /// Dominant color — computed lazily via ArtworkCache on first access.
    /// Returns nil if artwork is unavailable or not yet computed.
    var cachedColor: Color? {
        ArtworkCache.shared.dominantColor(forAlbumID: id)
    }

    var isAppleDigitalMaster: Bool { tracks.contains(where: { $0.isAppleDigitalMaster }) }
    static func == (lhs: Album, rhs: Album) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}
