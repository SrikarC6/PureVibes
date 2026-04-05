import Foundation
import CoreData
import AppKit
import OSLog

private let logger = Logger(subsystem: "com.purevibes.app", category: "PersistenceService")

// MARK: - PersistenceService

@MainActor
class PersistenceService {
    static let shared = PersistenceService()

    nonisolated let container: NSPersistentContainer
    var activeBookmarks: [URL] = []

    private init() {
        // Programmatic CoreData model — no .xcdatamodeld required
        let model = PersistenceService.buildModel()
        container = NSPersistentContainer(name: "PureVibes", managedObjectModel: model)

        container.loadPersistentStores { description, error in
            if let error = error {
                logger.error("CoreData load failed: \(error.localizedDescription)")
            } else {
                logger.info("CoreData store loaded: \(description.url?.absoluteString ?? "unknown")")
            }
        }
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    private var context: NSManagedObjectContext { container.viewContext }

    // MARK: - Model Definition

    private static func buildModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()

        // CachedAlbum entity
        let albumEntity = NSEntityDescription()
        albumEntity.name = "CachedAlbum"
        albumEntity.managedObjectClassName = NSManagedObject.self.description()
        albumEntity.properties = [
            attribute("title", .stringAttributeType),
            attribute("artist", .stringAttributeType),
            attribute("albumArtist", .stringAttributeType, optional: true),
            binaryAttribute("artworkData", optional: true),  // External binary storage
            attribute("directoryBookmark", .binaryDataAttributeType, optional: true),
            attribute("cachedAt", .dateAttributeType),
        ]

        // CachedTrack entity
        let trackEntity = NSEntityDescription()
        trackEntity.name = "CachedTrack"
        trackEntity.managedObjectClassName = NSManagedObject.self.description()
        trackEntity.properties = [
            attribute("url", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("artist", .stringAttributeType),
            attribute("album", .stringAttributeType),
            attribute("duration", .doubleAttributeType, optional: true),
            attribute("trackNumber", .integer32AttributeType, optional: true),
            attribute("discNumber", .integer32AttributeType, optional: true),
            binaryAttribute("waveformData", optional: true),  // External binary storage
            attribute("cachedAt", .dateAttributeType),
            attribute("lastModified", .dateAttributeType, optional: true),
        ]

        // CachedFavorite entity
        let favoriteEntity = NSEntityDescription()
        favoriteEntity.name = "CachedFavorite"
        favoriteEntity.managedObjectClassName = NSManagedObject.self.description()
        favoriteEntity.properties = [
            attribute("trackURL", .stringAttributeType),
            attribute("addedAt", .dateAttributeType),
        ]

        // UserRating entity
        let ratingEntity = NSEntityDescription()
        ratingEntity.name = "UserRating"
        ratingEntity.managedObjectClassName = NSManagedObject.self.description()
        ratingEntity.properties = [
            attribute("trackURL", .stringAttributeType),
            attribute("rating", .integer16AttributeType),
            attribute("ratedAt", .dateAttributeType),
        ]

        // SecurityScopedBookmark entity
        let bookmarkEntity = NSEntityDescription()
        bookmarkEntity.name = "SecurityScopedBookmark"
        bookmarkEntity.managedObjectClassName = NSManagedObject.self.description()
        bookmarkEntity.properties = [
            attribute("directoryPath", .stringAttributeType),
            attribute("bookmarkData", .binaryDataAttributeType),
            attribute("createdAt", .dateAttributeType),
        ]

        // QueueState entity (for restoring queue/playback)
        let queueStateEntity = NSEntityDescription()
        queueStateEntity.name = "QueueState"
        queueStateEntity.managedObjectClassName = NSManagedObject.self.description()
        queueStateEntity.properties = [
            attribute("trackURLs", .transformableAttributeType, optional: true),
            attribute("currentIndex", .integer32AttributeType),
            attribute("playbackPosition", .doubleAttributeType),
            attribute("savedAt", .dateAttributeType),
        ]

        model.entities = [albumEntity, trackEntity, favoriteEntity, ratingEntity, bookmarkEntity, queueStateEntity]
        return model
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = type
        attr.isOptional = optional
        return attr
    }

    /// Create a binary attribute with external storage enabled.
    /// External storage lets Core Data store large blobs on disk instead of inline in the SQLite row.
    private static func binaryAttribute(
        _ name: String,
        optional: Bool = false
    ) -> NSAttributeDescription {
        let attr = NSAttributeDescription()
        attr.name = name
        attr.attributeType = .binaryDataAttributeType
        attr.isOptional = optional
        attr.allowsExternalBinaryDataStorage = true
        return attr
    }

    // MARK: - Security Scoped Bookmarks

    func saveBookmark(for url: URL) {
        do {
            let bookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "SecurityScopedBookmark")
            fetch.predicate = NSPredicate(format: "directoryPath == %@", url.path)
            let existing = try context.fetch(fetch)
            existing.forEach { context.delete($0) }

            let entity = NSEntityDescription.insertNewObject(forEntityName: "SecurityScopedBookmark", into: context)
            entity.setValue(url.path, forKey: "directoryPath")
            entity.setValue(bookmarkData, forKey: "bookmarkData")
            entity.setValue(Date(), forKey: "createdAt")
            try context.save()
            logger.info("Bookmark saved for: \(url.path)")
        } catch {
            logger.error("Failed to save bookmark: \(error.localizedDescription)")
        }
    }

    func loadBookmarks() -> [URL] {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "SecurityScopedBookmark")
        do {
            let results = try context.fetch(fetch)
            return results.compactMap { obj -> URL? in
                guard let data = obj.value(forKey: "bookmarkData") as? Data else { return nil }
                var isStale = false
                do {
                    let url = try URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
                    if isStale {
                        logger.warning("Stale bookmark for \(url.path), re-saving")
                        saveBookmark(for: url)
                    }
                    return url
                } catch {
                    logger.error("Failed to resolve bookmark: \(error.localizedDescription)")
                    return nil
                }
            }
        } catch {
            logger.error("Failed to load bookmarks: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Favorites (Hard Delete)

    func saveFavorite(trackURL: String) {
        do {
            let entity = NSEntityDescription.insertNewObject(forEntityName: "CachedFavorite", into: context)
            entity.setValue(trackURL, forKey: "trackURL")
            entity.setValue(Date(), forKey: "addedAt")
            try context.save()
        } catch {
            logger.error("Failed to save favorite: \(error.localizedDescription)")
        }
    }

    func removeFavorite(trackURL: String) {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedFavorite")
        fetch.predicate = NSPredicate(format: "trackURL == %@", trackURL)
        do {
            let results = try context.fetch(fetch)
            results.forEach { context.delete($0) }
            try context.save()
        } catch {
            logger.error("Failed to remove favorite: \(error.localizedDescription)")
        }
    }

    func loadFavoriteURLs() -> Set<String> {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedFavorite")
        do {
            let results = try context.fetch(fetch)
            return Set(results.compactMap { $0.value(forKey: "trackURL") as? String })
        } catch {
            logger.error("Failed to load favorites: \(error.localizedDescription)")
            return []
        }
    }

    // MARK: - Ratings

    func setRating(trackURL: String, rating: Int) {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "UserRating")
        fetch.predicate = NSPredicate(format: "trackURL == %@", trackURL)
        do {
            let existing = try context.fetch(fetch)
            existing.forEach { context.delete($0) }

            let entity = NSEntityDescription.insertNewObject(forEntityName: "UserRating", into: context)
            entity.setValue(trackURL, forKey: "trackURL")
            entity.setValue(Int16(rating), forKey: "rating")
            entity.setValue(Date(), forKey: "ratedAt")
            try context.save()
        } catch {
            logger.error("Failed to set rating: \(error.localizedDescription)")
        }
    }

    func getRating(trackURL: String) -> Int? {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "UserRating")
        fetch.predicate = NSPredicate(format: "trackURL == %@", trackURL)
        do {
            let results = try context.fetch(fetch)
            return results.first?.value(forKey: "rating") as? Int
        } catch {
            logger.error("Failed to get rating: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Waveform Cache

    nonisolated func cacheWaveform(trackURL: String, data: [CGFloat]) {
        let bgContext = container.newBackgroundContext()
        bgContext.perform {
            do {
                let encoded = try JSONEncoder().encode(data)
                let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedTrack")
                fetch.predicate = NSPredicate(format: "url == %@", trackURL)
                if let existing = try bgContext.fetch(fetch).first {
                    existing.setValue(encoded, forKey: "waveformData")
                }
                try bgContext.save()
            } catch {
                logger.error("Failed to cache waveform: \(error.localizedDescription)")
            }
        }
    }

    func loadCachedWaveform(trackURL: String) -> [CGFloat]? {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedTrack")
        fetch.predicate = NSPredicate(format: "url == %@", trackURL)
        do {
            guard let result = try context.fetch(fetch).first,
                  let data = result.value(forKey: "waveformData") as? Data else { return nil }
            return try JSONDecoder().decode([CGFloat].self, from: data)
        } catch {
            logger.error("Failed to load cached waveform: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Queue State Persistence

    func saveQueueState(trackURLs: [String], currentIndex: Int, playbackPosition: Double) {
        do {
            // Delete existing
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "QueueState")
            let existing = try context.fetch(fetch)
            existing.forEach { context.delete($0) }

            let entity = NSEntityDescription.insertNewObject(forEntityName: "QueueState", into: context)
            let encoded = try JSONEncoder().encode(trackURLs)
            entity.setValue(encoded, forKey: "trackURLs")
            entity.setValue(Int32(currentIndex), forKey: "currentIndex")
            entity.setValue(playbackPosition, forKey: "playbackPosition")
            entity.setValue(Date(), forKey: "savedAt")
            try context.save()
        } catch {
            logger.error("Failed to save queue state: \(error.localizedDescription)")
        }
    }

    func loadQueueState() -> (trackURLs: [String], currentIndex: Int, playbackPosition: Double)? {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "QueueState")
        do {
            guard let result = try context.fetch(fetch).first,
                  let urlData = result.value(forKey: "trackURLs") as? Data,
                  let urls = try? JSONDecoder().decode([String].self, from: urlData),
                  let index = result.value(forKey: "currentIndex") as? Int32,
                  let position = result.value(forKey: "playbackPosition") as? Double else { return nil }
            return (urls, Int(index), position)
        } catch {
            logger.error("Failed to load queue state: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Library Caching

    var cacheVersion: Int {
        get { UserDefaults.standard.integer(forKey: "LibraryCacheVersion") }
        set { UserDefaults.standard.set(newValue, forKey: "LibraryCacheVersion") }
    }

    /// Save albums to Core Data.
    /// Artwork data is passed directly — NOT read from ArtworkCache (which is volatile NSCache).
    func saveAlbums(_ albums: [Album], artworkData: [UUID: Data] = [:]) {
        // Snapshot artwork data on the calling thread before entering background context
        let artworkSnapshot = artworkData
        let context = container.newBackgroundContext()
        context.perform {
            let albumFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedAlbum")
            let deleteAlbums = NSBatchDeleteRequest(fetchRequest: albumFetch)
            
            let trackFetch = NSFetchRequest<NSFetchRequestResult>(entityName: "CachedTrack")
            let deleteTracks = NSBatchDeleteRequest(fetchRequest: trackFetch)
            
            do {
                try context.execute(deleteAlbums)
                try context.execute(deleteTracks)
                context.reset()
                
                let now = Date()
                for (index, album) in albums.enumerated() {
                    autoreleasepool {
                        let albumEntity = NSEntityDescription.insertNewObject(forEntityName: "CachedAlbum", into: context)
                        albumEntity.setValue(album.title, forKey: "title")
                        albumEntity.setValue(album.artist, forKey: "artist")
                        if let albumArtist = album.albumArtist { albumEntity.setValue(albumArtist, forKey: "albumArtist") }
                        albumEntity.setValue(now, forKey: "cachedAt")
                        
                        // Use artwork data from the passed-in dictionary (not volatile cache)
                        if let artData = artworkSnapshot[album.id] {
                            albumEntity.setValue(artData, forKey: "artworkData")
                        }
                        
                        for track in album.tracks {
                            do {
                                try self.saveTrack(track, in: context, cachedAt: now)
                            } catch {
                                logger.error("Skipping track \(track.url.lastPathComponent): \(error.localizedDescription)")
                            }
                        }
                    }

                    // Periodic save every 20 albums to bound CoreData memory growth
                    if (index + 1) % 20 == 0 {
                        do {
                            try context.save()
                            context.reset()
                        } catch {
                            logger.error("Periodic save failed: \(error.localizedDescription)")
                        }
                    }
                }
                try context.save()
                logger.info("Saved \(albums.count) albums, \(artworkSnapshot.count) with artwork data")
            } catch {
                logger.error("Failed to save albums cache: \(error.localizedDescription)")
            }
        }
    }

    func saveTrack(_ track: Track) {
        let context = container.newBackgroundContext()
        context.perform {
            do {
                try self.saveTrack(track, in: context, cachedAt: Date())
                try context.save()
            } catch {
                logger.error("Failed to save single track: \(error.localizedDescription)")
            }
        }
    }

    private nonisolated func saveTrack(_ track: Track, in context: NSManagedObjectContext, cachedAt: Date) throws {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedTrack")
        fetch.predicate = NSPredicate(format: "url == %@", track.url.absoluteString)
        
        let existing = try context.fetch(fetch)
        let entity = existing.first ?? NSEntityDescription.insertNewObject(forEntityName: "CachedTrack", into: context)
            
        entity.setValue(track.url.absoluteString, forKey: "url")
        entity.setValue(track.title, forKey: "title")
        entity.setValue(track.artist, forKey: "artist")
        entity.setValue(track.album, forKey: "album")
        if let duration = track.duration { entity.setValue(duration, forKey: "duration") }
        if let trackNum = track.trackNumber { entity.setValue(Int32(trackNum), forKey: "trackNumber") }
        if let discNum = track.discNumber { entity.setValue(Int32(discNum), forKey: "discNumber") }
        entity.setValue(cachedAt, forKey: "cachedAt")
        // Store the file's filesystem modification date for incremental scanning
        if let attrs = try? FileManager.default.attributesOfItem(atPath: track.url.path),
           let modDate = attrs[.modificationDate] as? Date {
            entity.setValue(modDate, forKey: "lastModified")
        }
    }

    /// Load cached albums using a background context to avoid pinning blobs in viewContext.
    /// Returns lightweight Album values (no artwork — artwork is fed to ArtworkCache separately).
    func loadCachedAlbums() -> (albums: [Album], artworkEntries: [(albumID: UUID, data: Data)])? {
        // Use a background context for heavy materialization to avoid pinning in viewContext
        let bgContext = container.newBackgroundContext()
        var resultAlbums: [Album] = []
        var resultArtwork: [(albumID: UUID, data: Data)] = []

        bgContext.performAndWait {
            let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedAlbum")
            do {
                let results = try bgContext.fetch(fetch)
                if results.isEmpty { return }

                let sevenDaysAgo = Date().addingTimeInterval(-7 * 86400)

                let trackFetch = NSFetchRequest<NSManagedObject>(entityName: "CachedTrack")
                let trackResults = try bgContext.fetch(trackFetch)
                var albumTracks: [String: [Track]] = [:]

                for tObj in trackResults {
                    guard let urlStr = tObj.value(forKey: "url") as? String,
                          let url = URL(string: urlStr),
                          let cachedAt = tObj.value(forKey: "cachedAt") as? Date,
                          cachedAt > sevenDaysAgo else { continue }

                    var track = Track(url: url)
                    track.title = (tObj.value(forKey: "title") as? String) ?? track.title
                    track.artist = (tObj.value(forKey: "artist") as? String) ?? track.artist
                    track.album = (tObj.value(forKey: "album") as? String) ?? track.album
                    if let duration = tObj.value(forKey: "duration") as? Double { track.duration = duration }
                    if let trackNum = tObj.value(forKey: "trackNumber") as? Int32 { track.trackNumber = Int(trackNum) }
                    if let discNum = tObj.value(forKey: "discNumber") as? Int32 { track.discNumber = Int(discNum) }

                    // Group by album name ONLY — multi-artist albums have different track artists
                    // than the resolved album artist, so including artist would split tracks
                    let key = track.album
                    albumTracks[key, default: []].append(track)
                }

                for res in results {
                    autoreleasepool {
                        guard let cachedAt = res.value(forKey: "cachedAt") as? Date,
                              cachedAt > sevenDaysAgo else { return }

                        let title = (res.value(forKey: "title") as? String) ?? "Unknown Album"
                        let artist = (res.value(forKey: "artist") as? String) ?? "Unknown Artist"
                        let albumArtist = res.value(forKey: "albumArtist") as? String
                        let key = title

                        let tracks = albumTracks[key]?.sorted {
                            let d1 = $0.discNumber ?? 1
                            let d2 = $1.discNumber ?? 1
                            if d1 != d2 { return d1 < d2 }
                            return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
                        } ?? []

                        if !tracks.isEmpty {
                            let album = Album(
                                title: title,
                                artist: artist,
                                albumArtist: albumArtist,
                                artworkSourceURL: tracks.first?.url,
                                tracks: tracks
                            )
                            resultAlbums.append(album)

                            // Extract artwork data for cache population (not decoded here)
                            if let artData = res.value(forKey: "artworkData") as? Data {
                                resultArtwork.append((albumID: album.id, data: artData))
                            }
                        }
                    }
                }
            } catch {
                logger.error("Failed to load cached albums: \(error.localizedDescription)")
            }

            // Reset the background context to release all managed objects and blob references
            bgContext.reset()
        }

        return resultAlbums.isEmpty ? nil : (resultAlbums, resultArtwork)
    }

    func loadCachedTrack(url: String) -> Track? {
        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedTrack")
        fetch.predicate = NSPredicate(format: "url == %@", url)
        do {
            guard let tObj = try context.fetch(fetch).first,
                  let urlStr = tObj.value(forKey: "url") as? String,
                  let trackUrl = URL(string: urlStr),
                  let cachedAt = tObj.value(forKey: "cachedAt") as? Date,
                  cachedAt > Date().addingTimeInterval(-7 * 86400)
            else { 
                logger.info("Cached track expired, will re-scan: \(url)")
                return nil 
            }
            
            var track = Track(url: trackUrl)
            track.title = (tObj.value(forKey: "title") as? String) ?? track.title
            track.artist = (tObj.value(forKey: "artist") as? String) ?? track.artist
            track.album = (tObj.value(forKey: "album") as? String) ?? track.album
            if let duration = tObj.value(forKey: "duration") as? Double { track.duration = duration }
            if let trackNum = tObj.value(forKey: "trackNumber") as? Int32 { track.trackNumber = Int(trackNum) }
            if let discNum = tObj.value(forKey: "discNumber") as? Int32 { track.discNumber = Int(discNum) }
            
            return track
        } catch {
            logger.error("Failed to load cached track: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Incremental Scanning

    /// Compares filesystem modification dates against cached `lastModified` dates.
    /// Returns URLs categorized as new, modified, or unchanged.
    func detectNewAndModifiedFiles(allAudioURLs: [URL]) -> (new: [URL], modified: [URL], unchanged: [URL]) {
        var newURLs: [URL] = []
        var modifiedURLs: [URL] = []
        var unchangedURLs: [URL] = []

        let fetch = NSFetchRequest<NSManagedObject>(entityName: "CachedTrack")
        do {
            let cachedTracks = try context.fetch(fetch)
            var cachedByURL: [String: NSManagedObject] = [:]
            for obj in cachedTracks {
                if let urlStr = obj.value(forKey: "url") as? String {
                    cachedByURL[urlStr] = obj
                }
            }

            for audioURL in allAudioURLs {
                let urlStr = audioURL.absoluteString
                if let cachedObj = cachedByURL[urlStr] {
                    // File exists in cache — check if modified
                    let cachedModDate = cachedObj.value(forKey: "lastModified") as? Date
                    let fileModDate = (try? FileManager.default.attributesOfItem(atPath: audioURL.path))?[.modificationDate] as? Date

                    if let cached = cachedModDate, let file = fileModDate, file > cached {
                        modifiedURLs.append(audioURL)
                    } else {
                        unchangedURLs.append(audioURL)
                    }
                } else {
                    // New file — not in cache
                    newURLs.append(audioURL)
                }
            }
        } catch {
            logger.error("Failed to detect changes: \(error.localizedDescription)")
            // If fetch fails, treat all as new
            return (allAudioURLs, [], [])
        }

        logger.info("Incremental scan: \(newURLs.count) new, \(modifiedURLs.count) modified, \(unchangedURLs.count) unchanged")
        return (newURLs, modifiedURLs, unchangedURLs)
    }

    /// Merges new albums into an existing album list without destroying existing album IDs.
    /// Albums are matched by title+artist key. New albums are appended; modified ones update tracks.
    func mergeNewAlbums(_ newAlbums: [Album], into existingAlbums: inout [Album]) {
        for newAlbum in newAlbums {
            let key = "\(newAlbum.title)||||\(newAlbum.artist)"
            if let existingIdx = existingAlbums.firstIndex(where: { "\($0.title)||||\($0.artist)" == key }) {
                // Update existing album: merge tracks
                var existingTracks = existingAlbums[existingIdx].tracks
                let existingURLs = Set(existingTracks.map { $0.url.absoluteString })
                for track in newAlbum.tracks {
                    if existingURLs.contains(track.url.absoluteString) {
                        // Replace modified track
                        if let trackIdx = existingTracks.firstIndex(where: { $0.url.absoluteString == track.url.absoluteString }) {
                            existingTracks[trackIdx] = track
                        }
                    } else {
                        existingTracks.append(track)
                    }
                }
                // Re-sort by disc/track number
                existingTracks.sort {
                    let d1 = $0.discNumber ?? 1
                    let d2 = $1.discNumber ?? 1
                    if d1 != d2 { return d1 < d2 }
                    return ($0.trackNumber ?? 0) < ($1.trackNumber ?? 0)
                }
                existingAlbums[existingIdx].tracks = existingTracks
            } else {
                // Brand new album
                existingAlbums.append(newAlbum)
            }
        }
        // Re-sort albums alphabetically
        existingAlbums.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    // MARK: - Purge

    func purgeAllCache() {
        let entityNames = ["CachedAlbum", "CachedTrack", "CachedFavorite", "UserRating", "SecurityScopedBookmark", "QueueState"]
        for name in entityNames {
            let fetch = NSFetchRequest<NSFetchRequestResult>(entityName: name)
            let deleteRequest = NSBatchDeleteRequest(fetchRequest: fetch)
            do {
                try context.execute(deleteRequest)
            } catch {
                logger.error("Failed to purge \(name): \(error.localizedDescription)")
            }
        }
        do { try context.save() } catch { logger.error("Failed to save after purge: \(error.localizedDescription)") }
        logger.info("All caches purged")
    }
}
