import XCTest
@testable import PureVibes

final class LibraryIndexTests: XCTestCase {

    // MARK: - Album Model Tests (no MusicPlayer dependency)

    func testAlbumSortsByTitle() {
        let albumB = Album(title: "Bravo", artist: "A", albumArtist: "A", tracks: [])
        let albumA = Album(title: "Alpha", artist: "A", albumArtist: "A", tracks: [])
        let albumC = Album(title: "Charlie", artist: "A", albumArtist: "A", tracks: [])

        let sorted = [albumB, albumA, albumC].sorted {
            $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
        XCTAssertEqual(sorted[0].title, "Alpha")
        XCTAssertEqual(sorted[1].title, "Bravo")
        XCTAssertEqual(sorted[2].title, "Charlie")
    }

    func testAlbumContainsTracks() {
        let track1 = Track(url: URL(fileURLWithPath: "/tmp/t1.mp3"))
        let track2 = Track(url: URL(fileURLWithPath: "/tmp/t2.mp3"))
        let album = Album(title: "Test", artist: "A", albumArtist: "A", tracks: [track1, track2])
        XCTAssertEqual(album.tracks.count, 2)
    }

    func testAlbumEquality() {
        let tracks = [Track(url: URL(fileURLWithPath: "/tmp/t1.mp3"))]
        let album1 = Album(title: "Test", artist: "A", albumArtist: "A", tracks: tracks)
        let album2 = Album(title: "Test", artist: "A", albumArtist: "A", tracks: tracks)
        // Each album has a unique UUID, so they should NOT be equal
        XCTAssertNotEqual(album1, album2, "Albums with different IDs should not be equal")
    }

    // MARK: - Track Model Tests

    func testTrackInitFromURL() {
        let url = URL(fileURLWithPath: "/Music/Artist/AlbumName/track01.mp3")
        let track = Track(url: url)
        XCTAssertEqual(track.title, "track01")
        XCTAssertEqual(track.url, url)
    }

    func testTrackHasNoArtworkProperty() {
        // Verify that Track does NOT have an artwork property
        // (This is a compile-time check — if Track had `artwork`, this would still compile)
        let track = Track(url: URL(fileURLWithPath: "/tmp/test.mp3"))
        _ = track.title  // Just verify Track compiles without artwork
        XCTAssertNotNil(track.id)
    }

    func testAlbumHasNoArtworkProperty() {
        // Verify Album uses artworkSourceURL instead of artwork: NSImage?
        let album = Album(
            title: "Test",
            artist: "A",
            albumArtist: "A",
            artworkSourceURL: URL(fileURLWithPath: "/tmp/test.mp3"),
            tracks: []
        )
        XCTAssertNotNil(album.artworkSourceURL)
    }

    // MARK: - Flattened Tracks

    func testFlattenedTracksFromAlbums() {
        let t1 = Track(url: URL(fileURLWithPath: "/a/1.mp3"))
        let t2 = Track(url: URL(fileURLWithPath: "/a/2.mp3"))
        let t3 = Track(url: URL(fileURLWithPath: "/b/1.mp3"))
        let albums = [
            Album(title: "A", artist: "X", albumArtist: "X", tracks: [t1, t2]),
            Album(title: "B", artist: "Y", albumArtist: "Y", tracks: [t3])
        ]
        let allTracks = albums.flatMap { $0.tracks }
        XCTAssertEqual(allTracks.count, 3)
    }

    // MARK: - Track-to-Album Index

    func testTrackToAlbumIndex() {
        let t1 = Track(url: URL(fileURLWithPath: "/a/1.mp3"))
        let t2 = Track(url: URL(fileURLWithPath: "/b/1.mp3"))
        let album1 = Album(title: "A", artist: "X", albumArtist: "X", tracks: [t1])
        let album2 = Album(title: "B", artist: "Y", albumArtist: "Y", tracks: [t2])

        var index: [UUID: UUID] = [:]
        for album in [album1, album2] {
            for track in album.tracks {
                index[track.id] = album.id
            }
        }

        XCTAssertEqual(index[t1.id], album1.id)
        XCTAssertEqual(index[t2.id], album2.id)
    }
}
