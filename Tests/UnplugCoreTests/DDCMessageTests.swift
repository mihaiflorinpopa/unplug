import XCTest
@testable import UnplugCore

/// Message layouts and checksums from the VESA DDC/CI and MCCS standards.
final class DDCMessageTests: XCTestCase {
    func testGetBrightnessRequest() {
        // 0x6E ^ 0x51 ^ 0x82 ^ 0x01 ^ 0x10 = 0xAC
        XCTAssertEqual(DDCMessage.getBrightnessRequest(), [0x82, 0x01, 0x10, 0xAC])
    }

    func testSetBrightnessRequest() {
        XCTAssertEqual(DDCMessage.setBrightnessRequest(0.5), [0x84, 0x03, 0x10, 0x00, 0x32, 0x9A])
        XCTAssertEqual(DDCMessage.setBrightnessRequest(1), [0x84, 0x03, 0x10, 0x00, 0x64, 0xCC])
        XCTAssertEqual(DDCMessage.setBrightnessRequest(0), [0x84, 0x03, 0x10, 0x00, 0x00, 0xA8])
    }

    func testSetBrightnessClampsOutOfRangeLevels() {
        XCTAssertEqual(DDCMessage.setBrightnessRequest(1.5), DDCMessage.setBrightnessRequest(1))
        XCTAssertEqual(DDCMessage.setBrightnessRequest(-1), DDCMessage.setBrightnessRequest(0))
    }

    func testReadsBrightnessFromReply() {
        // Maximum 100, current 50.
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
        XCTAssertEqual(DDCMessage.brightness(fromReply: reply), 0.5)
    }

    func testUsesTheMonitorsOwnMaximum() {
        // Maximum 200, current 50.
        let reply: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0xC8, 0x00, 0x32, 0x00, 0x00]
        XCTAssertEqual(DDCMessage.brightness(fromReply: reply), 0.25)
    }

    func testRejectsErrorAndMismatchedReplies() {
        let unsupported: [UInt8] = [0x6E, 0x88, 0x02, 0x01, 0x10, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
        let otherCode: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x12, 0x00, 0x00, 0x64, 0x00, 0x32, 0x00, 0x00]
        let zeroMaximum: [UInt8] = [0x6E, 0x88, 0x02, 0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x32, 0x00, 0x00]
        let empty = [UInt8](repeating: 0, count: 12)
        let short: [UInt8] = [0x6E, 0x88, 0x02]
        for reply in [unsupported, otherCode, zeroMaximum, empty, short] {
            XCTAssertNil(DDCMessage.brightness(fromReply: reply))
        }
    }
}
