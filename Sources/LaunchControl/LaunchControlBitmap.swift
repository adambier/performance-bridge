// A picture for the Launch Control XL 3's or Launch Control 3's 128 × 64 screen, and the SysEx 09h
// message that sends one. Source: Novation's Launch Control XL 3 programmer's reference guide
// (version 1.0), "Bitmap": target 20h (stationary display) or 21h (global temporary display), then
// 64 rows of 19 bytes, 7 pixels per byte with the highest bit leftmost (the last byte of a row has
// five unused bits), then a terminator the guide prints as 7Fh; the device answers when it is
// ready for the next picture. On an XL 3 (docs/LAUNCH-CONTROL-XL3.md, test 21) the target that
// works is 35h, the stationary display as "Configure displays" numbers it (20h drew nothing), the
// message ends with F7h alone, a set bit lights a pixel, the first byte is the top left, and the
// reply comes after about 68 ms.

import Foundation

/// A 128 × 64 one-bit picture for a Launch Control's screen.
public struct LaunchControlBitmap: Equatable, Sendable {
    /// The screen's width in pixels.
    public static let width = 128
    /// The screen's height in pixels.
    public static let height = 64
    /// Bytes per row in the message: 7 pixels each, so 19 bytes cover 128 pixels with 5 bits over.
    public static let bytesPerRow = 19

    /// The pixels, row by row from the top, `true` for a set bit.
    public private(set) var pixels: [Bool]

    /// A picture with every pixel clear.
    public init() {
        pixels = Array(repeating: false, count: Self.width * Self.height)
    }

    /// Whether the pixel at column `x` and row `y` (from the top left) is set; `false` off the
    /// screen.
    public subscript(x: Int, y: Int) -> Bool {
        get {
            guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return false }
            return pixels[y * Self.width + x]
        }
        set {
            guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return }
            pixels[y * Self.width + x] = newValue
        }
    }

    /// Sets (or clears) every pixel in a rectangle, clipped to the screen.
    public mutating func fill(x: Int, y: Int, width: Int, height: Int, _ on: Bool = true) {
        for row in max(0, y)..<min(Self.height, y + height) {
            for column in max(0, x)..<min(Self.width, x + width) {
                pixels[row * Self.width + column] = on
            }
        }
    }

    /// The picture packed as the message carries it: 64 rows of 19 bytes, 7 pixels per byte, the
    /// highest of the 7 bits leftmost; 1,216 bytes, each 0–127.
    public var packed: [UInt8] {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(Self.height * Self.bytesPerRow)
        for row in 0..<Self.height {
            for byte in 0..<Self.bytesPerRow {
                var value: UInt8 = 0
                for bit in 0..<7 {
                    let column = byte * 7 + bit
                    if column < Self.width, pixels[row * Self.width + column] {
                        value |= 0x40 >> UInt8(bit)
                    }
                }
                bytes.append(value)
            }
        }
        return bytes
    }
}

extension LaunchControlOutgoing {
    /// The bitmap message: the model's SysEx header, 09h, `target` (35h for the stationary display,
    /// test 21), the packed picture, then F7h. The guide prints the end as 7Fh, which can't end a
    /// SysEx message; `extraEnd` adds a 7Fh before the F7h, for the probe only, since F7h alone has
    /// been observed to work.
    public static func bitmap(_ picture: LaunchControlBitmap, target: UInt8, extraEnd: Bool = false,
                              model: LaunchControlModel = .xl3) -> [UInt8] {
        model.sysExHeader + [0x09, target & 0x7F] + picture.packed + (extraEnd ? [0x7F, 0xF7] : [0xF7])
    }
}
