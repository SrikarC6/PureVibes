import SwiftUI

struct Album: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let artist: String 
    let albumArtist: String?
    /// Lightweight reference to the first track URL for on-demand artwork extraction.
    /// Artwork is NEVER stored as decoded NSImage — it lives only in ArtworkCache.
    let artworkSourceURL: URL?
    var tracks: [Track]

    init(title: String, artist: String, albumArtist: String?, artworkSourceURL: URL? = nil, tracks: [Track]) {
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.artworkSourceURL = artworkSourceURL
        self.tracks = tracks
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
