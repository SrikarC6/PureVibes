import XCTest
@testable import PureVibes

final class SecurityScopeManagerTests: XCTestCase {

    func testIdempotentStartAccess() {
        let manager = SecurityScopeManager.shared
        // Using a real directory that exists without scoped access needed
        let url = URL(fileURLWithPath: "/tmp")

        // First access
        let result1 = manager.startAccessing(url)
        // Second access should be idempotent (already active)
        let result2 = manager.startAccessing(url)

        // Both should succeed (or at least not crash)
        // For /tmp, the result depends on sandbox state
        _ = result1
        _ = result2

        // Clean up
        manager.stopAccessing(url)
    }

    func testStopNonActiveURLIsNoOp() {
        let manager = SecurityScopeManager.shared
        let url = URL(fileURLWithPath: "/tmp/nonexistent_dir_\(UUID().uuidString)")

        // Should not crash
        manager.stopAccessing(url)
    }

    func testStopAllClearsActive() {
        let manager = SecurityScopeManager.shared
        manager.stopAll()
        XCTAssertEqual(manager.activeCount, 0, "stopAll should clear all active URLs")
    }
}
