import Foundation
import OSLog

private let logger = Logger(subsystem: "com.purevibes.app", category: "SecurityScopeManager")

/// Manages security-scoped resource access to ensure balanced start/stop calls.
/// Each successful `startAccessingSecurityScopedResource()` is tracked and will
/// be matched by a `stopAccessingSecurityScopedResource()` when no longer needed.
final class SecurityScopeManager {
    static let shared = SecurityScopeManager()

    /// Currently active security-scoped URLs.
    private var activeURLs: Set<URL> = []

    private init() {}

    /// Start accessing a security-scoped URL. Only calls the system API if not already active.
    /// Returns true if access was granted (or was already active).
    @discardableResult
    func startAccessing(_ url: URL) -> Bool {
        if activeURLs.contains(url) {
            logger.debug("Already accessing: \(url.path)")
            return true
        }
        let granted = url.startAccessingSecurityScopedResource()
        if granted {
            activeURLs.insert(url)
            logger.info("Started accessing: \(url.path)")
        } else {
            logger.warning("Access denied for: \(url.path)")
        }
        return granted
    }

    /// Stop accessing a security-scoped URL.
    func stopAccessing(_ url: URL) {
        guard activeURLs.contains(url) else {
            logger.debug("Not active, skip stop: \(url.path)")
            return
        }
        url.stopAccessingSecurityScopedResource()
        activeURLs.remove(url)
        logger.info("Stopped accessing: \(url.path)")
    }

    /// Stop all active security-scoped URLs.
    func stopAll() {
        for url in activeURLs {
            url.stopAccessingSecurityScopedResource()
            logger.info("Stopped accessing: \(url.path)")
        }
        activeURLs.removeAll()
    }

    /// Replace all active URLs with a new set.
    /// Stops old URLs, starts new ones. Idempotent for URLs in both sets.
    func replaceAll(with newURLs: [URL]) {
        let newSet = Set(newURLs)
        // Stop URLs that are no longer needed
        let toStop = activeURLs.subtracting(newSet)
        for url in toStop {
            url.stopAccessingSecurityScopedResource()
            logger.info("Stopped accessing (replaced): \(url.path)")
        }
        // Start URLs that are new
        let toStart = newSet.subtracting(activeURLs)
        for url in toStart {
            let granted = url.startAccessingSecurityScopedResource()
            if granted {
                logger.info("Started accessing (replaced): \(url.path)")
            } else {
                logger.warning("Access denied during replace: \(url.path)")
            }
        }
        activeURLs = newSet.filter { url in
            activeURLs.contains(url) || url.startAccessingSecurityScopedResource()
        }
        // Re-build accurately: keep existing + newly granted
        var result = Set<URL>()
        for url in activeURLs.intersection(newSet) {
            result.insert(url)
        }
        for url in toStart {
            if url.startAccessingSecurityScopedResource() || activeURLs.contains(url) {
                result.insert(url)
            }
        }
        activeURLs = result
    }

    /// The set of currently active URLs (read-only for testing).
    var currentlyActive: Set<URL> { activeURLs }

    /// Number of currently active scoped accesses.
    var activeCount: Int { activeURLs.count }
}
