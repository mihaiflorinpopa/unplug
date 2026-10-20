import XCTest
@testable import UnplugCore

final class LinkedBrightnessTests: XCTestCase {
    let displays = ["BUILTIN", "A", "B"].map {
        Display(uuid: $0, displayID: 1, name: $0, isBuiltin: $0 == "BUILTIN", isConnected: true)
    }

    func testLinksTwoOrMoreDisplaysInTheirOrder() {
        XCTAssertEqual(displays.linkedGroup(["B", "A"]).map(\.uuid), ["A", "B"])
    }

    func testOneLinkedDisplayIsNoGroup() {
        XCTAssertEqual(displays.linkedGroup(["A"]), [])
    }

    func testIgnoresLinkedDisplaysThatAreGone() {
        // A linked monitor that's unplugged no longer appears in the list.
        XCTAssertEqual(displays.linkedGroup(["A", "GONE"]), [])
    }
}
