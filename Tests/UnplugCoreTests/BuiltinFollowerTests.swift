import XCTest
@testable import UnplugCore

final class BuiltinFollowerTests: XCTestCase {
    func builtin(on: Bool) -> Display {
        Display(uuid: "BUILTIN", displayID: 1, name: "Built-in Retina Display", isBuiltin: true, isConnected: on)
    }

    func monitor(_ uuid: String, on: Bool = true) -> Display {
        Display(uuid: uuid, displayID: 2, name: "Monitor \(uuid)", isBuiltin: false, isConnected: on)
    }

    func testTurnsBuiltinOffWhenAMonitorConnects() {
        var follower = BuiltinFollower([builtin(on: true)])
        XCTAssertEqual(follower.update([builtin(on: true), monitor("A")], turnOffWithExternal: true), .turnOff)
    }

    func testLeavesBuiltinOnWhenTheOptionIsOff() {
        var follower = BuiltinFollower([builtin(on: true)])
        XCTAssertEqual(follower.update([builtin(on: true), monitor("A")], turnOffWithExternal: false), .none)
    }

    func testDoesNotTurnBuiltinOffAgainWhileTheMonitorStays() {
        // The user turned the built-in screen back on with the monitor still in.
        var follower = BuiltinFollower([builtin(on: true), monitor("A")])
        XCTAssertEqual(follower.update([builtin(on: true), monitor("A")], turnOffWithExternal: true), .none)
    }

    func testTurnsBuiltinOnWhenTheLastMonitorIsUnplugged() {
        for option in [true, false] {
            var follower = BuiltinFollower([builtin(on: false), monitor("A")])
            XCTAssertEqual(follower.update([builtin(on: false)], turnOffWithExternal: option), .turnOn)
            XCTAssertTrue(follower.restorePending)
        }
    }

    func testCountsAMonitorTurnedOffInUnplugAsGone() {
        var follower = BuiltinFollower([builtin(on: false), monitor("A"), monitor("B", on: false)])
        XCTAssertEqual(follower.update([builtin(on: false), monitor("B", on: false)], turnOffWithExternal: false), .turnOn)
    }

    func testKeepsTryingOnLaterChangesUntilTheBuiltinIsBack() {
        var follower = BuiltinFollower([builtin(on: false), monitor("A")])
        XCTAssertEqual(follower.update([builtin(on: false)], turnOffWithExternal: false), .turnOn)
        // The first try failed, so the next change (or wake) asks again.
        XCTAssertEqual(follower.update([builtin(on: false)], turnOffWithExternal: false), .turnOn)
        XCTAssertEqual(follower.update([builtin(on: true)], turnOffWithExternal: false), .none)
        XCTAssertFalse(follower.restorePending)
    }

    func testRestoredStopsTrying() {
        var follower = BuiltinFollower([builtin(on: false), monitor("A")])
        XCTAssertEqual(follower.update([builtin(on: false)], turnOffWithExternal: false), .turnOn)
        follower.restored()
        XCTAssertFalse(follower.restorePending)
    }

    func testPluggingAMonitorBackInCancelsTheRestore() {
        var follower = BuiltinFollower([builtin(on: false), monitor("A")])
        XCTAssertEqual(follower.update([builtin(on: false)], turnOffWithExternal: true), .turnOn)
        XCTAssertEqual(follower.update([builtin(on: false), monitor("A")], turnOffWithExternal: true), .none)
        XCTAssertFalse(follower.restorePending)
    }

    func testUnpluggingOneOfTwoMonitorsLeavesBuiltinOff() {
        var follower = BuiltinFollower([builtin(on: false), monitor("A"), monitor("B")])
        XCTAssertEqual(follower.update([builtin(on: false), monitor("A")], turnOffWithExternal: false), .none)
    }

    func testDoesNothingWithoutABuiltinScreen() {
        var follower = BuiltinFollower([monitor("A")])
        XCTAssertEqual(follower.update([], turnOffWithExternal: true), .none)
    }
}
