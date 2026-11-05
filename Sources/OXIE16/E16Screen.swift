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
                for column in 0..<E16Font.glyphWidth where bits & (0b100 >> column) != 0 {
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

/// A 3×5 pixel font: capitals, digits, and the punctuation channel names use. Each glyph is five
/// rows of three bits, the leftmost pixel in bit 2.
public enum E16Font {
    /// A glyph's width in pixels.
    public static let glyphWidth = 3
    /// A glyph's height in pixels.
    public static let glyphHeight = 5
    /// The distance from one character's left edge to the next, in pixels (one pixel of space).
    public static let advance = 4

    /// The glyph for a scalar, or a box for one the font lacks.
    public static func glyph(_ scalar: Unicode.Scalar) -> [UInt8] {
        glyphs[scalar] ?? box
    }

    static let box: [UInt8] = [0b111, 0b101, 0b101, 0b101, 0b111]

    static let glyphs: [Unicode.Scalar: [UInt8]] = [
        " ": [0b000, 0b000, 0b000, 0b000, 0b000],
        "A": [0b010, 0b101, 0b111, 0b101, 0b101],
        "B": [0b110, 0b101, 0b110, 0b101, 0b110],
        "C": [0b011, 0b100, 0b100, 0b100, 0b011],
        "D": [0b110, 0b101, 0b101, 0b101, 0b110],
        "E": [0b111, 0b100, 0b110, 0b100, 0b111],
        "F": [0b111, 0b100, 0b110, 0b100, 0b100],
        "G": [0b011, 0b100, 0b101, 0b101, 0b011],
        "H": [0b101, 0b101, 0b111, 0b101, 0b101],
        "I": [0b111, 0b010, 0b010, 0b010, 0b111],
        "J": [0b001, 0b001, 0b001, 0b101, 0b010],
        "K": [0b101, 0b101, 0b110, 0b101, 0b101],
        "L": [0b100, 0b100, 0b100, 0b100, 0b111],
        "M": [0b101, 0b111, 0b111, 0b101, 0b101],
        "N": [0b110, 0b101, 0b101, 0b101, 0b101],
        "O": [0b010, 0b101, 0b101, 0b101, 0b010],
        "P": [0b110, 0b101, 0b110, 0b100, 0b100],
        "Q": [0b010, 0b101, 0b101, 0b110, 0b011],
        "R": [0b110, 0b101, 0b110, 0b101, 0b101],
        "S": [0b011, 0b100, 0b010, 0b001, 0b110],
        "T": [0b111, 0b010, 0b010, 0b010, 0b010],
        "U": [0b101, 0b101, 0b101, 0b101, 0b111],
        "V": [0b101, 0b101, 0b101, 0b101, 0b010],
        "W": [0b101, 0b101, 0b111, 0b111, 0b101],
        "X": [0b101, 0b101, 0b010, 0b101, 0b101],
        "Y": [0b101, 0b101, 0b010, 0b010, 0b010],
        "Z": [0b111, 0b001, 0b010, 0b100, 0b111],
        "0": [0b111, 0b101, 0b101, 0b101, 0b111],
        "1": [0b010, 0b110, 0b010, 0b010, 0b111],
        "2": [0b110, 0b001, 0b010, 0b100, 0b111],
        "3": [0b111, 0b001, 0b011, 0b001, 0b111],
        "4": [0b101, 0b101, 0b111, 0b001, 0b001],
        "5": [0b111, 0b100, 0b110, 0b001, 0b110],
        "6": [0b011, 0b100, 0b111, 0b101, 0b111],
        "7": [0b111, 0b001, 0b010, 0b010, 0b010],
        "8": [0b111, 0b101, 0b111, 0b101, 0b111],
        "9": [0b111, 0b101, 0b111, 0b001, 0b110],
        "/": [0b001, 0b001, 0b010, 0b100, 0b100],
        "-": [0b000, 0b000, 0b111, 0b000, 0b000],
        "+": [0b000, 0b010, 0b111, 0b010, 0b000],
        ".": [0b000, 0b000, 0b000, 0b000, 0b010],
        ",": [0b000, 0b000, 0b000, 0b010, 0b100],
        ":": [0b000, 0b010, 0b000, 0b010, 0b000],
        "'": [0b010, 0b010, 0b000, 0b000, 0b000],
        "!": [0b010, 0b010, 0b010, 0b000, 0b010],
        "?": [0b110, 0b001, 0b010, 0b000, 0b010],
        "(": [0b001, 0b010, 0b010, 0b010, 0b001],
        ")": [0b100, 0b010, 0b010, 0b010, 0b100],
        "<": [0b001, 0b010, 0b100, 0b010, 0b001],
        ">": [0b100, 0b010, 0b001, 0b010, 0b100],
        "=": [0b000, 0b111, 0b000, 0b111, 0b000],
        "&": [0b010, 0b101, 0b010, 0b101, 0b011],
        "#": [0b101, 0b111, 0b101, 0b111, 0b101],
        "*": [0b101, 0b010, 0b111, 0b010, 0b101],
        "_": [0b000, 0b000, 0b000, 0b000, 0b111],
        "%": [0b101, 0b001, 0b010, 0b100, 0b101],
    ]
}

extension E16Outgoing {
    /// OLED FRAMEBUFFER (`06 02`): the whole screen, replacing the label layout (and vice versa).
    public static func framebuffer(_ screen: E16Screen) -> [UInt8] {
        message([0x06, 0x02], payload: screen.framebuffer)
    }
}
