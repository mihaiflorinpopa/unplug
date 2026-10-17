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
}
