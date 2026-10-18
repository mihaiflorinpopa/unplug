import XCTest
@testable import UnplugCore

final class DisplayMatchTests: XCTestCase {
    let displays = [
        Display(uuid: "AAAA-1111", displayID: 1, name: "Built-in Retina Display", isBuiltin: true, isConnected: true),
        Display(uuid: "BBBB-2222", displayID: 3, name: "LG UltraFine", isBuiltin: false, isConnected: true),
        Display(uuid: "CCCC-3333", displayID: 4, name: "LG HDR 4K", isBuiltin: false, isConnected: false),
    ]

    func testMatchesByID() throws {
        XCTAssertEqual(try DisplayManager.match("3", in: displays).uuid, "BBBB-2222")
    }

    func testMatchesByUUIDIgnoringCase() throws {
        XCTAssertEqual(try DisplayManager.match("cccc-3333", in: displays).displayID, 4)
    }

    func testMatchesByPartOfName() throws {
        XCTAssertEqual(try DisplayManager.match("ultrafine", in: displays).displayID, 3)
    }

    func testAmbiguousName() {
        XCTAssertThrowsError(try DisplayManager.match("LG", in: displays)) { error in
            guard case UnplugError.ambiguous = error else { return XCTFail("\(error)") }
        }
    }

    func testNoMatch() {
        XCTAssertThrowsError(try DisplayManager.match("Dell", in: displays)) { error in
            XCTAssertEqual(error as? UnplugError, .notFound("Dell"))
        }
    }

    /// WindowServer's stand-in display, as logged after the last monitor was
    /// unplugged (v: 0x756e6b6e m: 0x76697274), and an ASUS PG27UCDM.
    func testRecognisesTheWindowServerPlaceholder() {
        func fourCC(_ text: String) -> UInt32 { text.utf8.reduce(0) { $0 << 8 | UInt32($1) } }
        XCTAssertTrue(DisplayManager.isPlaceholder(vendor: fourCC("unkn"), model: fourCC("virt")))
        XCTAssertFalse(DisplayManager.isPlaceholder(vendor: 0x06B3, model: 0x27F5))
    }
}
