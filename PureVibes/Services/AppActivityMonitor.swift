import SwiftUI
import Combine
import AppKit

/// Centralized visibility/activity monitor for the app.
/// Views and animation controllers observe `isAppVisible` to gate expensive
/// background work (e.g., CloudView 15 Hz redraws, spinner animations).
@MainActor
final class AppActivityMonitor: ObservableObject {
    static let shared = AppActivityMonitor()

    @Published var isAppVisible: Bool = true
    @Published var isAppActive: Bool = true

    private init() {
        // Occlusion state (window fully hidden behind others / minimized)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeOcclusionStateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isAppVisible = NSApp?.occlusionState.contains(.visible) ?? true
            }
        }

        // Active/inactive state (app in foreground vs background)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isAppActive = true }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.isAppActive = false }
        }
    }

    /// Whether animations and heavy rendering should be active.
    /// True only when the app is both visible and active.
    var shouldAnimate: Bool {
        isAppVisible && isAppActive
    }
}
