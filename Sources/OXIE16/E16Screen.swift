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
            let leftmost = UInt8(1) << UInt8(max(glyph.width, 5) - 1)
            for (row, bits) in glyph.rows.enumerated() {
                for column in 0..<glyph.width where bits & (leftmost >> UInt8(column)) != 0 {
                    for dy in 0..<scale {
                        for dx in 0..<scale { set(cursor + column * scale + dx, y + row * scale + dy) }
                    }
                }
            }
            cursor += (glyph.width + E16Font.gap) * scale
        }
        return cursor - x
    }

    /// The width `text` takes at `scale`, in pixels, without the gap after its last character.
    public static func width(of text: String, scale: Int = 1) -> Int {
        let scalars = text.uppercased().unicodeScalars
        guard !scalars.isEmpty else { return 0 }
        return (scalars.reduce(0) { $0 + E16Font.glyph($1).width + E16Font.gap } - E16Font.gap) * scale
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

/// One character of the font: five pixels wide (up to seven for a wide one, "∞"), seven tall;
/// each row's leftmost pixel is bit 4 (bit `width - 1` for a wide glyph), and a narrow glyph
/// ("1", "/", "I", "L") uses only its first `width` columns.
public struct E16Glyph: Sendable {
    /// How many columns the glyph uses: up to five, or seven for a wide glyph.
    public let width: Int
    /// The seven rows, top first, the leftmost pixel in bit 4 (bit `width - 1` if wider).
    public let rows: [UInt8]
}

/// A 5×7 pixel font, proportionally spaced: capitals, digits (4 wide, so a pair like "P15/16"
/// fits a label), and the punctuation channel names use, one pixel between characters. (3×5 and 4×6 fonts were tried first and were too small to
/// read on the device; Adam, 2026-11-04.)
public enum E16Font {
    /// A glyph's height in pixels.
    public static let glyphHeight = 7
    /// The space between characters, in pixels.
    public static let gap = 1

    /// The glyph for a scalar, or a box for one the font lacks.
    public static func glyph(_ scalar: Unicode.Scalar) -> E16Glyph {
        glyphs[scalar] ?? box
    }

    static let box = E16Glyph(width: 5, rows: [0b11111, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11111])

    static let glyphs: [Unicode.Scalar: E16Glyph] = [
        " ": E16Glyph(width: 3, rows: [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000]),
        "A": E16Glyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]),
        "B": E16Glyph(width: 5, rows: [0b11110, 0b10001, 0b10001, 0b11110, 0b10001, 0b10001, 0b11110]),
        "C": E16Glyph(width: 5, rows: [0b01110, 0b10001, 0b10000, 0b10000, 0b10000, 0b10001, 0b01110]),
        "D": E16Glyph(width: 5, rows: [0b11110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b11110]),
        "E": E16Glyph(width: 5, rows: [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b11111]),
        "F": E16Glyph(width: 5, rows: [0b11111, 0b10000, 0b10000, 0b11110, 0b10000, 0b10000, 0b10000]),
        "G": E16Glyph(width: 5, rows: [0b01110, 0b10001, 0b10000, 0b10111, 0b10001, 0b10001, 0b01111]),
        "H": E16Glyph(width: 5, rows: [0b10001, 0b10001, 0b10001, 0b11111, 0b10001, 0b10001, 0b10001]),
        "I": E16Glyph(width: 3, rows: [0b11100, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b11100]),
        "J": E16Glyph(width: 5, rows: [0b00111, 0b00010, 0b00010, 0b00010, 0b00010, 0b10010, 0b01100]),
        "K": E16Glyph(width: 5, rows: [0b10001, 0b10010, 0b10100, 0b11000, 0b10100, 0b10010, 0b10001]),
        "L": E16Glyph(width: 3, rows: [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b11100]),
        "M": E16Glyph(width: 5, rows: [0b10001, 0b11011, 0b10101, 0b10101, 0b10001, 0b10001, 0b10001]),
        "N": E16Glyph(width: 5, rows: [0b10001, 0b11001, 0b10101, 0b10011, 0b10001, 0b10001, 0b10001]),
        "O": E16Glyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]),
        "P": E16Glyph(width: 5, rows: [0b11110, 0b10001, 0b10001, 0b11110, 0b10000, 0b10000, 0b10000]),
        "Q": E16Glyph(width: 5, rows: [0b01110, 0b10001, 0b10001, 0b10001, 0b10101, 0b10010, 0b01101]),
        "R": E16Glyph(width: 5, rows: [0b11110, 0b10001, 0b10001, 0b11110, 0b10100, 0b10010, 0b10001]),
        "S": E16Glyph(width: 5, rows: [0b01111, 0b10000, 0b10000, 0b01110, 0b00001, 0b00001, 0b11110]),
        "T": E16Glyph(width: 5, rows: [0b11111, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100, 0b00100]),
        "U": E16Glyph(width: 5, rows: [0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b10001, 0b01110]),
        "V": E16Glyph(width: 5, rows: [0b10001, 0b10001, 0b10001, 0b10001, 0b01010, 0b01010, 0b00100]),
        "W": E16Glyph(width: 5, rows: [0b10001, 0b10001, 0b10001, 0b10101, 0b10101, 0b11011, 0b10001]),
        "X": E16Glyph(width: 5, rows: [0b10001, 0b10001, 0b01010, 0b00100, 0b01010, 0b10001, 0b10001]),
        "Y": E16Glyph(width: 5, rows: [0b10001, 0b10001, 0b01010, 0b00100, 0b00100, 0b00100, 0b00100]),
        "Z": E16Glyph(width: 5, rows: [0b11111, 0b00001, 0b00010, 0b00100, 0b01000, 0b10000, 0b11111]),
        "0": E16Glyph(width: 4, rows: [0b01100, 0b10010, 0b10010, 0b10010, 0b10010, 0b10010, 0b01100]),
        "1": E16Glyph(width: 3, rows: [0b01000, 0b11000, 0b01000, 0b01000, 0b01000, 0b01000, 0b11100]),
        "2": E16Glyph(width: 4, rows: [0b01100, 0b10010, 0b00010, 0b00100, 0b01000, 0b10000, 0b11110]),
        "3": E16Glyph(width: 4, rows: [0b11100, 0b00010, 0b00010, 0b01100, 0b00010, 0b00010, 0b11100]),
        "4": E16Glyph(width: 4, rows: [0b00100, 0b01100, 0b10100, 0b10100, 0b11110, 0b00100, 0b00100]),
        "5": E16Glyph(width: 4, rows: [0b11110, 0b10000, 0b11100, 0b00010, 0b00010, 0b00010, 0b11100]),
        "6": E16Glyph(width: 4, rows: [0b01100, 0b10000, 0b10000, 0b11100, 0b10010, 0b10010, 0b01100]),
        "7": E16Glyph(width: 4, rows: [0b11110, 0b00010, 0b00010, 0b00100, 0b01000, 0b01000, 0b01000]),
        "8": E16Glyph(width: 4, rows: [0b01100, 0b10010, 0b10010, 0b01100, 0b10010, 0b10010, 0b01100]),
        "9": E16Glyph(width: 4, rows: [0b01100, 0b10010, 0b10010, 0b01110, 0b00010, 0b00010, 0b01100]),
        "/": E16Glyph(width: 2, rows: [0b01000, 0b01000, 0b01000, 0b10000, 0b10000, 0b10000, 0b00000]),
        "-": E16Glyph(width: 3, rows: [0b00000, 0b00000, 0b00000, 0b11100, 0b00000, 0b00000, 0b00000]),
        // Infinity, for "-∞" (off): the font has no lowercase, so "-oo" drew as "-OO"; seven
        // wide, since five was too small to read (Adam, 2026-11-05).
        "∞": E16Glyph(width: 7, rows: [0b0000000, 0b0000000, 0b0110110, 0b1001001, 0b1001001, 0b0110110, 0b0000000]),
        "+": E16Glyph(width: 5, rows: [0b00000, 0b00100, 0b00100, 0b11111, 0b00100, 0b00100, 0b00000]),
        ".": E16Glyph(width: 1, rows: [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b10000]),
        ",": E16Glyph(width: 2, rows: [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b01000, 0b10000]),
        ":": E16Glyph(width: 1, rows: [0b00000, 0b10000, 0b00000, 0b00000, 0b00000, 0b10000, 0b00000]),
        "'": E16Glyph(width: 1, rows: [0b10000, 0b10000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000]),
        "!": E16Glyph(width: 1, rows: [0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b00000, 0b10000]),
        "?": E16Glyph(width: 5, rows: [0b01110, 0b10001, 0b00001, 0b00010, 0b00100, 0b00000, 0b00100]),
        "(": E16Glyph(width: 2, rows: [0b01000, 0b10000, 0b10000, 0b10000, 0b10000, 0b10000, 0b01000]),
        ")": E16Glyph(width: 2, rows: [0b10000, 0b01000, 0b01000, 0b01000, 0b01000, 0b01000, 0b10000]),
        "<": E16Glyph(width: 4, rows: [0b00010, 0b00100, 0b01000, 0b10000, 0b01000, 0b00100, 0b00010]),
        ">": E16Glyph(width: 4, rows: [0b10000, 0b01000, 0b00100, 0b00010, 0b00100, 0b01000, 0b10000]),
        "=": E16Glyph(width: 5, rows: [0b00000, 0b00000, 0b11111, 0b00000, 0b11111, 0b00000, 0b00000]),
        "&": E16Glyph(width: 5, rows: [0b01100, 0b10010, 0b10100, 0b01000, 0b10101, 0b10010, 0b01101]),
        "#": E16Glyph(width: 5, rows: [0b01010, 0b01010, 0b11111, 0b01010, 0b11111, 0b01010, 0b01010]),
        "*": E16Glyph(width: 5, rows: [0b00000, 0b10101, 0b01110, 0b11111, 0b01110, 0b10101, 0b00000]),
        "_": E16Glyph(width: 5, rows: [0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b00000, 0b11111]),
        "%": E16Glyph(width: 5, rows: [0b11001, 0b11010, 0b00010, 0b00100, 0b01000, 0b10110, 0b10011]),
    ]
}

extension E16Outgoing {
    /// OLED FRAMEBUFFER (`06 02`): the whole screen, replacing the label layout (and vice versa).
    public static func framebuffer(_ screen: E16Screen) -> [UInt8] {
        message([0x06, 0x02], payload: screen.framebuffer)
    }
}
