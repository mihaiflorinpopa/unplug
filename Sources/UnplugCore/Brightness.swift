import CoreGraphics
import Foundation
import IOKit

/// Reads and sets display brightness. macOS has no public brightness API, so this
/// uses two private routes, both resolved at runtime so a missing symbol only
/// turns the feature off:
///
/// - DisplayServices, the framework Control Center uses, for the built-in screen
///   and Apple displays (Studio Display, Pro Display XDR).
/// - DDC/CI over the display's I2C channel (`IOAVService`) for other external
///   monitors on Apple Silicon. Monitors that don't answer DDC get no control.
///
/// Calls can block for a moment while a monitor answers, so call them off the
/// main thread. Safe to share between threads: the only state is the cache of
/// DDC channels, which a lock guards.
public final class Brightness: @unchecked Sendable {
    public init() {}

    /// Brightness from 0 to 1, or nil if this display can't be controlled.
    public func get(_ display: Display) -> Double? {
        guard display.isConnected else { return nil }
        if let level = DisplayServices.get(display.displayID) { return level }
        guard let service = ddcService(for: display.displayID) else { return nil }
        return DDC.readBrightness(service)
    }

    /// Sets brightness from 0 to 1. Returns false if the display didn't accept it.
    @discardableResult
    public func set(_ display: Display, _ level: Double) -> Bool {
        let level = min(max(level, 0), 1)
        if DisplayServices.get(display.displayID) != nil {
            return DisplayServices.set(display.displayID, level)
        }
        guard let service = ddcService(for: display.displayID) else { return false }
        return DDC.writeBrightness(service, level)
    }

    // MARK: - Matching displays to their DDC channel

    private var services: [CGDirectDisplayID: CFTypeRef] = [:]
    private let lock = NSLock()

    /// Forgets cached DDC channels, for when displays are added or removed.
    public func reset() {
        lock.lock()
        services.removeAll()
        lock.unlock()
    }

    private func ddcService(for displayID: CGDirectDisplayID) -> CFTypeRef? {
        lock.lock()
        defer { lock.unlock() }
        if let service = services[displayID] { return service }
        guard CGDisplayIsBuiltin(displayID) == 0 else { return nil }

        let byLocation = DDC.servicesByFramebufferPath()
        if let location = DDC.displayLocation(displayID), let service = byLocation[location] {
            services[displayID] = service
            return service
        }
        // Without a location match, pair only when there's no doubt: one
        // external display that needs DDC and one DDC channel.
        let ddcDisplays = Self.onlineExternalDisplays().filter { DisplayServices.get($0) == nil }
        if ddcDisplays == [displayID], byLocation.count == 1, let service = byLocation.values.first {
            services[displayID] = service
            return service
        }
        return nil
    }

    private static func onlineExternalDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        let capacity = count
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(capacity))
        guard CGGetOnlineDisplayList(capacity, &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).filter { CGDisplayIsBuiltin($0) == 0 }
    }
}

/// The DisplayServices private framework.
private enum DisplayServices {
    private typealias CanChange = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias Get = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Set = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let handle = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as _: T.Type) -> T? {
        guard let handle, let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static let canChange = symbol("DisplayServicesCanChangeBrightness", as: CanChange.self)
    private static let getBrightness = symbol("DisplayServicesGetBrightness", as: Get.self)
    private static let setBrightness = symbol("DisplayServicesSetBrightness", as: Set.self)

    static func get(_ id: CGDirectDisplayID) -> Double? {
        guard let canChange, let getBrightness, canChange(id) else { return nil }
        var level: Float = 0
        guard getBrightness(id, &level) == 0 else { return nil }
        return Double(level)
    }

    static func set(_ id: CGDirectDisplayID, _ level: Double) -> Bool {
        guard let setBrightness else { return false }
        return setBrightness(id, Float(level)) == 0
    }
}

/// DDC/CI (VESA MCCS) over IOAVService, Apple Silicon only. VCP code 0x10 is
/// brightness.
private enum DDC {
    private typealias CreateWithService = @convention(c) (CFAllocator?, io_service_t) -> Unmanaged<CFTypeRef>?
    private typealias ReadI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias WriteI2C = @convention(c) (CFTypeRef, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn
    private typealias CreateInfoDictionary = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFDictionary>?

    private static func symbol<T>(_ library: String, _ name: String, as _: T.Type) -> T? {
        guard let handle = dlopen(library, RTLD_LAZY), let pointer = dlsym(handle, name) else { return nil }
        return unsafeBitCast(pointer, to: T.self)
    }

    private static let iokit = "/System/Library/Frameworks/IOKit.framework/IOKit"
    private static let createWithService = symbol(iokit, "IOAVServiceCreateWithService", as: CreateWithService.self)
    private static let readI2C = symbol(iokit, "IOAVServiceReadI2C", as: ReadI2C.self)
    private static let writeI2C = symbol(iokit, "IOAVServiceWriteI2C", as: WriteI2C.self)
    private static let createInfoDictionary = symbol(
        "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
        "CoreDisplay_DisplayCreateInfoDictionary", as: CreateInfoDictionary.self)

    private static let chipAddress: UInt32 = 0x37
    private static let dataAddress: UInt32 = 0x51

    /// The IORegistry path of the display's framebuffer, as CoreDisplay reports it.
    static func displayLocation(_ id: CGDirectDisplayID) -> String? {
        guard let info = createInfoDictionary?(id)?.takeRetainedValue() as? [String: Any] else { return nil }
        return info["IODisplayLocation"] as? String
    }

    /// External DDC channels keyed by the framebuffer they belong to. In the
    /// IORegistry each framebuffer (AppleCLCD2 / IOMobileFramebufferShim) comes
    /// before the DCPAVServiceProxy that talks to its monitor.
    static func servicesByFramebufferPath() -> [String: CFTypeRef] {
        guard let createWithService else { return [:] }
        var iterator: io_iterator_t = 0
        let root = IORegistryGetRootEntry(kIOMainPortDefault)
        defer { IOObjectRelease(root) }
        guard IORegistryEntryCreateIterator(
            root, kIOServicePlane, IOOptionBits(kIORegistryIterateRecursively), &iterator) == KERN_SUCCESS
        else { return [:] }
        defer { IOObjectRelease(iterator) }

        var result: [String: CFTypeRef] = [:]
        var framebufferPath: String?
        var entry = IOIteratorNext(iterator)
        while entry != 0 {
            var name = [CChar](repeating: 0, count: 128)
            IORegistryEntryGetName(entry, &name)
            let entryName = String(cString: name)
            if entryName == "AppleCLCD2" || entryName == "IOMobileFramebufferShim" {
                var path = [CChar](repeating: 0, count: 1024)
                if IORegistryEntryGetPath(entry, kIOServicePlane, &path) == KERN_SUCCESS {
                    framebufferPath = String(cString: path)
                }
            } else if entryName == "DCPAVServiceProxy", let path = framebufferPath {
                let location = IORegistryEntryCreateCFProperty(
                    entry, "Location" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
                if location == "External", let service = createWithService(kCFAllocatorDefault, entry)?.takeRetainedValue() {
                    result[path] = service
                }
                framebufferPath = nil
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iterator)
        }
        return result
    }

    static func readBrightness(_ service: CFTypeRef) -> Double? {
        guard let readI2C, let writeI2C else { return nil }
        for _ in 0..<3 {
            var request = DDCMessage.getBrightnessRequest()
            guard writeI2C(service, chipAddress, dataAddress, &request, UInt32(request.count)) == kIOReturnSuccess
            else { continue }
            usleep(50_000) // DDC/CI asks hosts to wait at least 40 ms before reading the reply

            var reply = [UInt8](repeating: 0, count: 12)
            guard readI2C(service, chipAddress, dataAddress, &reply, UInt32(reply.count)) == kIOReturnSuccess
            else { continue }
            guard let level = DDCMessage.brightness(fromReply: reply) else { continue }
            return level
        }
        return nil
    }

    static func writeBrightness(_ service: CFTypeRef, _ level: Double) -> Bool {
        guard let writeI2C else { return false }
        var request = DDCMessage.setBrightnessRequest(level)
        for _ in 0..<2 {
            if writeI2C(service, chipAddress, dataAddress, &request, UInt32(request.count)) == kIOReturnSuccess {
                return true
            }
            usleep(50_000)
        }
        return false
    }
}

/// DDC/CI messages for the brightness control (VESA MCCS VCP code 0x10), kept
/// apart from the I/O so they can be tested. The I2C layer adds the monitor's
/// address (0x6E) and the source address (0x51), and both count toward the
/// checksum, which is the XOR of every byte before it.
enum DDCMessage {
    static let brightnessCode: UInt8 = 0x10
    private static let destinationAddress: UInt8 = 0x6E
    private static let sourceAddress: UInt8 = 0x51

    /// "Get VCP Feature" for brightness.
    static func getBrightnessRequest() -> [UInt8] {
        withChecksum([0x82, 0x01, brightnessCode])
    }

    /// "Set VCP Feature" for brightness, on the monitor's usual 0–100 scale.
    static func setBrightnessRequest(_ level: Double) -> [UInt8] {
        let value = UInt16((min(max(level, 0), 1) * 100).rounded())
        return withChecksum([0x84, 0x03, brightnessCode, UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    /// Brightness from 0 to 1 from a "Get VCP Feature" reply: source address,
    /// length, 0x02 (reply), result (0 = ok), VCP code, type, maximum (2 bytes),
    /// current value (2 bytes), checksum. Some monitors send a wrong checksum,
    /// so the reply's shape is checked instead.
    static func brightness(fromReply reply: [UInt8]) -> Double? {
        guard reply.count >= 10, reply[2] == 0x02, reply[3] == 0x00, reply[4] == brightnessCode else { return nil }
        let maximum = Int(reply[6]) << 8 | Int(reply[7])
        let current = Int(reply[8]) << 8 | Int(reply[9])
        guard maximum > 0 else { return nil }
        return min(Double(current) / Double(maximum), 1)
    }

    private static func withChecksum(_ body: [UInt8]) -> [UInt8] {
        body + [body.reduce(destinationAddress ^ sourceAddress, ^)]
    }
}
