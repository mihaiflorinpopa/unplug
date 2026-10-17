import XCTest
@testable import UnplugCore

final class DisplayStoreTests: XCTestCase {
    var store: DisplayStore!

    override func setUp() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = DisplayStore(fileURL: dir.appendingPathComponent("disconnected.json"))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent())
    }

    func display(_ uuid: String) -> Display {
        Display(uuid: uuid, displayID: 2, name: "Studio Display", isBuiltin: false, isConnected: true)
    }

    func testEmptyWhenNoFile() {
        XCTAssertEqual(store.load(), [])
    }

    func testRememberStoresDisplayAsDisconnected() {
        store.remember(display("A"))
        XCTAssertEqual(store.load().map(\.uuid), ["A"])
        XCTAssertEqual(store.load().first?.isConnected, false)
    }

    func testRememberingTwiceKeepsOneEntry() {
        store.remember(display("A"))
        store.remember(display("A"))
        XCTAssertEqual(store.load().count, 1)
    }

    func testForget() {
        store.remember(display("A"))
        store.remember(display("B"))
        store.forget(uuid: "A")
        XCTAssertEqual(store.load().map(\.uuid), ["B"])
    }

    func testCorruptFileReadsAsEmpty() throws {
        try FileManager.default.createDirectory(
            at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        XCTAssertEqual(store.load(), [])
    }
}
