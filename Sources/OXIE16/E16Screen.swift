// The E16's screen drawn by the host: a 128×64 framebuffer in the SSD1306 page layout, with a
// small pixel font of this project's own, so a label can have more than the four characters of
// the firmware's own layout. Foundation only.

import Foundation

/// A 128×64 one-bit picture for the E16's OLED, and the small font drawn into it.
public struct E16Screen: Hashable, Sendable {
    /// The screen's width in pixels.
    public static let width = 128
    /// The screen's height in pixels.
    public static let height = 64

    /// The pixels, row-major, one byte per pixel (0 or 1), for simple drawing.
    private var pixels: [UInt8] = Array(repeating: 0, count: E16Screen.width * E16Screen.height)

    /// A blank screen.
    public init() {}

    /// Sets one pixel; off-screen pixels are ignored.
    public mutating func set(_ x: Int, _ y: Int, _ on: Bool = true) {
        guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return }
        pixels[y * Self.width + x] = on ? 1 : 0
    }

    /// Whether a pixel is on.
    public func pixel(_ x: Int, _ y: Int) -> Bool {
        guard (0..<Self.width).contains(x), (0..<Self.height).contains(y) else { return false }
        return pixels[y * Self.width + x] != 0
    }

    /// Draws a horizontal line.
    public mutating func line(y: Int, from x0: Int, to x1: Int) {
        for x in min(x0, x1)...max(x0, x1) { set(x, y) }
    }

    /// Draws `text` with the font at `scale` (1 or 2), its top-left corner at (x, y), and
    /// returns the width drawn. Characters the font lacks draw as a box. Lowercase letters are
    /// drawn as uppercase (the font has no lowercase).
    @discardableResult
    public mutating func draw(_ text: String, x: Int, y: Int, scale: Int = 1) -> Int {
        var cursor = x
        for scalar in text.uppercased().unicodeScalars {
            let glyph = E16Font.glyph(scalar)
            for (row, bits) in glyph.enumerated() {
                for column in 0..<E16Font.glyphWidth where bits & (0b1000 >> column) != 0 {
                    for dy in 0..<scale {
                        for dx in 0..<scale { set(cursor + column * scale + dx, y + row * scale + dy) }
                    }
                }
            }
            cursor += E16Font.advance * scale
        }
        return cursor - x
    }

    /// The width `text` takes at `scale`, in pixels.
    public static func width(of text: String, scale: Int = 1) -> Int {
        text.unicodeScalars.count * E16Font.advance * scale
    }

    /// The framebuffer as the OLED FRAMEBUFFER message wants it: 8 pages of 128 bytes, each byte
    /// a column of 8 pixels with the top pixel in bit 0 (the SSD1306 page layout).
    public var framebuffer: [UInt8] {
        var out = [UInt8](repeating: 0, count: Self.width * Self.height / 8)
        for page in 0..<(Self.height / 8) {
            for x in 0..<Self.width {
                var byte: UInt8 = 0
                for bit in 0..<8 where pixels[(page * 8 + bit) * Self.width + x] != 0 { byte |= 1 << UInt8(bit) }
                out[page * Self.width + x] = byte
            }
        }
        return out
    }

    /// The screen as text, one character per pixel, for tests and logs.
    public var art: String {
        (0..<Self.height).map { y in String((0..<Self.width).map { pixel($0, y) ? "#" : "." }) }.joined(separator: "\n")
    }
}

/// A 4×6 pixel font: capitals, digits, and the punctuation channel names use. Each glyph is six
/// rows of four bits, the leftmost pixel in bit 3. (A 3×5 font was tried first and was too small
/// to read on the device; Adam, 2026-11-04.)
public enum E16Font {
    /// A glyph's width in pixels.
    public static let glyphWidth = 4
    /// A glyph's height in pixels.
    public static let glyphHeight = 6
    /// The distance from one character's left edge to the next, in pixels (one pixel of space).
    public static let advance = 5

    /// The glyph for a scalar, or a box for one the font lacks.
    public static func glyph(_ scalar: Unicode.Scalar) -> [UInt8] {
        glyphs[scalar] ?? box
    }

    static let box: [UInt8] = [0b1111, 0b1001, 0b1001, 0b1001, 0b1001, 0b1111]

    static let glyphs: [Unicode.Scalar: [UInt8]] = [
        " ": [0b0000, 0b0000, 0b0000, 0b0000, 0b0000, 0b0000],
        "A": [0b0110, 0b1001, 0b1001, 0b1111, 0b1001, 0b1001],
        "B": [0b1110, 0b1001, 0b1110, 0b1001, 0b1001, 0b1110],
        "C": [0b0111, 0b1000, 0b1000, 0b1000, 0b1000, 0b0111],
        "D": [0b1110, 0b1001, 0b1001, 0b1001, 0b1001, 0b1110],
        "E": [0b1111, 0b1000, 0b1110, 0b1000, 0b1000, 0b1111],
        "F": [0b1111, 0b1000, 0b1110, 0b1000, 0b1000, 0b1000],
        "G": [0b0111, 0b1000, 0b1000, 0b1011, 0b1001, 0b0111],
        "H": [0b1001, 0b1001, 0b1111, 0b1001, 0b1001, 0b1001],
        "I": [0b1110, 0b0100, 0b0100, 0b0100, 0b0100, 0b1110],
        "J": [0b0001, 0b0001, 0b0001, 0b0001, 0b1001, 0b0110],
        "K": [0b1001, 0b1010, 0b1100, 0b1100, 0b1010, 0b1001],
        "L": [0b1000, 0b1000, 0b1000, 0b1000, 0b1000, 0b1111],
        "M": [0b1001, 0b1111, 0b1111, 0b1001, 0b1001, 0b1001],
        "N": [0b1001, 0b1101, 0b1111, 0b1011, 0b1001, 0b1001],
        "O": [0b0110, 0b1001, 0b1001, 0b1001, 0b1001, 0b0110],
        "P": [0b1110, 0b1001, 0b1001, 0b1110, 0b1000, 0b1000],
        "Q": [0b0110, 0b1001, 0b1001, 0b1001, 0b1010, 0b0101],
        "R": [0b1110, 0b1001, 0b1001, 0b1110, 0b1010, 0b1001],
        "S": [0b0111, 0b1000, 0b0110, 0b0001, 0b0001, 0b1110],
        "T": [0b1110, 0b0100, 0b0100, 0b0100, 0b0100, 0b0100],
        "U": [0b1001, 0b1001, 0b1001, 0b1001, 0b1001, 0b0110],
        "V": [0b1001, 0b1001, 0b1001, 0b1001, 0b0110, 0b0110],
        "W": [0b1001, 0b1001, 0b1001, 0b1111, 0b1111, 0b1001],
        "X": [0b1001, 0b1001, 0b0110, 0b0110, 0b1001, 0b1001],
        "Y": [0b1010, 0b1010, 0b1010, 0b0100, 0b0100, 0b0100],
        "Z": [0b1111, 0b0001, 0b0010, 0b0100, 0b1000, 0b1111],
        "0": [0b0110, 0b1001, 0b1011, 0b1101, 0b1001, 0b0110],
        "1": [0b0100, 0b1100, 0b0100, 0b0100, 0b0100, 0b1110],
        "2": [0b0110, 0b1001, 0b0001, 0b0010, 0b0100, 0b1111],
        "3": [0b1110, 0b0001, 0b0110, 0b0001, 0b0001, 0b1110],
        "4": [0b1001, 0b1001, 0b1001, 0b1111, 0b0001, 0b0001],
        "5": [0b1111, 0b1000, 0b1110, 0b0001, 0b0001, 0b1110],
        "6": [0b0110, 0b1000, 0b1110, 0b1001, 0b1001, 0b0110],
        "7": [0b1111, 0b0001, 0b0010, 0b0100, 0b0100, 0b0100],
        "8": [0b0110, 0b1001, 0b0110, 0b1001, 0b1001, 0b0110],
        "9": [0b0110, 0b1001, 0b1001, 0b0111, 0b0001, 0b0110],
        "/": [0b0001, 0b0001, 0b0010, 0b0100, 0b1000, 0b1000],
        "-": [0b0000, 0b0000, 0b1111, 0b0000, 0b0000, 0b0000],
        "+": [0b0000, 0b0100, 0b1110, 0b0100, 0b0000, 0b0000],
        ".": [0b0000, 0b0000, 0b0000, 0b0000, 0b0000, 0b0100],
        ",": [0b0000, 0b0000, 0b0000, 0b0000, 0b0100, 0b1000],
        ":": [0b0000, 0b0100, 0b0000, 0b0000, 0b0100, 0b0000],
        "'": [0b0100, 0b0100, 0b0000, 0b0000, 0b0000, 0b0000],
        "!": [0b0100, 0b0100, 0b0100, 0b0100, 0b0000, 0b0100],
        "?": [0b0110, 0b1001, 0b0010, 0b0100, 0b0000, 0b0100],
        "(": [0b0010, 0b0100, 0b0100, 0b0100, 0b0100, 0b0010],
        ")": [0b0100, 0b0010, 0b0010, 0b0010, 0b0010, 0b0100],
        "<": [0b0001, 0b0010, 0b0100, 0b0100, 0b0010, 0b0001],
        ">": [0b1000, 0b0100, 0b0010, 0b0010, 0b0100, 0b1000],
        "=": [0b0000, 0b1111, 0b0000, 0b1111, 0b0000, 0b0000],
        "&": [0b0100, 0b1010, 0b0100, 0b1011, 0b1010, 0b0101],
        "#": [0b0101, 0b1111, 0b0101, 0b0101, 0b1111, 0b0101],
        "*": [0b0000, 0b1010, 0b0100, 0b1010, 0b0000, 0b0000],
        "_": [0b0000, 0b0000, 0b0000, 0b0000, 0b0000, 0b1111],
        "%": [0b1001, 0b0001, 0b0010, 0b0100, 0b1000, 0b1001],
    ]
}

extension E16Outgoing {
    /// OLED FRAMEBUFFER (`06 02`): the whole screen, replacing the label layout (and vice versa).
    public static func framebuffer(_ screen: E16Screen) -> [UInt8] {
        message([0x06, 0x02], payload: screen.framebuffer)
    }
}
