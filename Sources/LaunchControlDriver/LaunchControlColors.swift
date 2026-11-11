// The Launch Control driver's text and colors: display field length, send labels, the button and
// row colors, exact RGB, brightness from level, shading, and the palette for TotalMix FX's colors.
// Pure functions and constants, moved out of LaunchControlDriver.swift unchanged (refactoring of
// 2026-11-04); the evidence is in docs/LAUNCH-CONTROL-XL3.md, tests 4, 13, 17, and 19.

import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif
#if canImport(LaunchControl)
import LaunchControl
#endif
#if canImport(SurfaceCore)
import SurfaceCore
#endif

extension LaunchControlDriver {

    /// The most characters a display field keeps: 20 (inference from the XL 3, test 5).
    public static let fieldLength = 20

    /// Roughly how wide a line of text is on the screen, in pixels of the 128, counting the gap
    /// after each character. The font is proportional and Novation doesn't give its widths, so these
    /// are estimates (an inference), measured from a photo of the XL 3's screen
    /// (docs/LAUNCH-CONTROL-XL3.md, test 22): capitals and digits about 9 pixels (a capital I about
    /// 5), most lowercase letters nearly as wide; a space about 5, from the spaces' offsets in two
    /// photos of padded lines (test 24; test 22's 3 was too small).
    public static func screenWidth(_ text: String) -> Double {
        text.reduce(0) { width, character in
            switch character {
            case "i", "l", "j", ",", ".", ":", ";", "!", "'", "|": return width + 4
            case "I": return width + 5
            case " ": return width + 5
            case "f", "t", "r", "(", ")", "-", "/", ">", "<": return width + 7
            case "m", "w", "M", "W": return width + 10.5
            default: return width + (character.isUppercase || character.isNumber ? 9 : 8.75)
            }
        }
    }

    /// Whether a line fits the screen's 128 pixels (`screenWidth`), with a little room to spare,
    /// since the widths are estimates; and the field's 20 characters.
    public static func fitsScreen(_ text: String) -> Bool {
        text.count <= fieldLength && screenWidth(text) <= 126
    }

    /// The label for a send: "> " and the output's name (AGENTS.md, house style).
    public static func sendLabel(_ name: String) -> String { "> " + name }

    /// Colors for the buttons and the navigation lights. Mute is orange and PFL yellow on every
    /// hardware controller, since the Roto-Control's firmware fixes those two and a host can only
    /// turn them on or off (docs/ROTO-CONTROL.md, section 3); a button that is off shows a dim
    /// shade of its color, so the two rows can still be told apart (Adam, 2026-11-02).
    /// The palette's first 40 colors have been seen to run as the guide's picture does
    /// (docs/LAUNCH-CONTROL-XL3.md, test 4), each hue a run of four from bright to dim: 5 red and
    /// 7 a darker red, 13 yellow and 15 a darker yellow, 3 white and 1 a dim grey; 9 orange and 11
    /// its dimmest (test 13).
    public static let muteOn: UInt8 = 9
    /// A mute button that is off: orange by exact RGB, dimmer than the palette's dimmest orange
    /// (11), so on and off differ more; chosen on the XL 3 with its LED brightness at 10 (Adam,
    /// 2026-11-02; docs/LAUNCH-CONTROL-XL3.md, test 19).
    public static let muteOff = LightColor.rgb(RGB(12, 4, 0))
    /// How a mute that is on while TotalMix FX's Mute Master is off shows: it flashes between bright
    /// and dim orange, `blinkPeriod` seconds each, drawn by the driver. The medium shade (10) was
    /// tried and was too close to the others to read, and the device has no flashing of its own
    /// (docs/LAUNCH-CONTROL-XL3.md, test 15; Adam, 2026-11-02).
    public static let blinkPeriod: Double = 0.5
    /// A PFL button that is on: yellow.
    public static let pflOn: UInt8 = 13
    /// A PFL button that is off: yellow by exact RGB, dimmer than the palette's dimmest yellow (15),
    /// chosen with `muteOff` (test 19).
    public static let pflOff = LightColor.rgb(RGB(16, 11, 0))
    /// Page and Track where they would move: white.
    public static let navigationOn: UInt8 = 3
    /// The Function button while the buttons are mute: PFL's color when off, as for any button that
    /// is off (Adam, 2026-11-02). The Launch Control 3's buttons, Function
    /// included, are taken to show colors as the XL 3's do (Adam, 2026-11-02; test 19 lit the
    /// XL 3's strip buttons).
    public static let functionIdle = pflOff
    /// The hue of a send row whose output is left white in TotalMix FX: teal (33) for the top row,
    /// magenta (53) for the XL 3's middle row; neither is one of TotalMix FX's eight colors (Adam,
    /// 2026-11-02, from the Tier 3 review of that date). On the XL 3 both have been told apart from
    /// blue, purple, and green (test 17); teal on its own was seen as cyan (test 18); cyan (37),
    /// tried first, looked too close to blue (test 17).
    public static let sendRowHues: [UInt8] = [33, 53]

    /// A light's color: a palette index (CC on channel 1), or an exact color (SysEx 01h 53h).
    public enum LightColor: Equatable, Sendable {
        /// A palette index, 0 for off.
        case palette(UInt8)
        /// An exact color.
        case rgb(RGB)
    }

    /// An exact color, each part 0–127.
    public struct RGB: Equatable, Sendable {
        /// Red, 0–127.
        public var red: UInt8
        /// Green, 0–127.
        public var green: UInt8
        /// Blue, 0–127.
        public var blue: UInt8

        /// A color from its three parts, each 0–127.
        public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            (self.red, self.green, self.blue) = (red, green, blue)
        }

        /// This color at `fraction` (0…1) of its brightness, each part rounded and a part that was
        /// lit kept at 1 or more, so the hue stays roughly the same (only roughly at small
        /// fractions, and a fraction of 0 is not dark: use `.palette(0)` for off).
        public func scaled(_ fraction: Double) -> RGB {
            guard fraction.isFinite else { return self }
            func part(_ value: UInt8) -> UInt8 {
                guard value > 0 else { return 0 }
                return UInt8(min(max((Double(value) * fraction).rounded(), 1), 127))
            }
            return RGB(part(red), part(green), part(blue))
        }
    }

    /// The exact color of each palette color the driver lights encoders with, for dimming. Orange
    /// has been seen to match its palette color on buttons (test 13; on encoders it has not been
    /// compared, an inference); yellow is set to the value that matched the buttons' yellow best,
    /// as the encoders show it (test 18); teal, magenta, blue, and white matched on encoders (test
    /// 17); purple's 16, 0, 127 is inferred from 20 looking slightly redder (16 itself not lit);
    /// red and green are read off the guide's palette picture (inference), and grey's is a guess.
    public static let paletteRGB: [UInt8: RGB] = [
        3: RGB(127, 127, 127),   // white
        1: RGB(40, 40, 40),      // grey (a guess)
        9: RGB(127, 40, 0),      // orange (test 13)
        5: RGB(127, 0, 0),       // red
        45: RGB(0, 0, 127),      // blue
        21: RGB(0, 127, 0),      // green
        13: RGB(127, 85, 0),     // yellow, as the encoders show the buttons' yellow (test 18)
        49: RGB(16, 0, 127),     // purple, for TotalMix FX's pink (test 17: 20 was a little redder)
        33: RGB(0, 127, 76),     // teal, the top send row's hue
        53: RGB(127, 0, 127),    // magenta, the middle send row's hue
    ]

    /// The device value (0–127) of the dimmest lit level, at the bottom of an encoder's travel:
    /// 9, 7, and 5 have been seen to dim in turn, and 4 and below to look dark (docs/
    /// LAUNCH-CONTROL-XL3.md, test 18).
    public static let dimmestValue = 5.0

    /// Palette colors an encoder shows as an exact color instead, at full brightness: palette
    /// yellow (13) has been seen to look greener on the encoders than on the buttons, and 127, 85, 0
    /// to match the buttons' yellow best of those tried; palette orange (9) matched (test 18). The
    /// Launch Control 3 gets the same, an inference from the XL 3.
    public static let encoderExactColors: Set<UInt8> = [13]

    /// An encoder's light at full brightness for a palette color: the palette color, or its exact
    /// color (`paletteRGB`) for those in `encoderExactColors`.
    public static func encoderColor(_ color: UInt8) -> LightColor {
        guard encoderExactColors.contains(color), let rgb = paletteRGB[color] else { return .palette(color) }
        return .rgb(rgb)
    }

    /// How bright a level or send encoder is, as a fraction of its color, for a fader position
    /// (0…1), when `levelBrightness` is on; `nil` for dark (−oo, or a position that isn't a
    /// number). The brightness falls geometrically from full at the top of the travel to `floor`
    /// at the bottom, so equal steps of fader travel give equal ratios of brightness (roughly
    /// equal per encoder value on the ARC scale; computed). On the XL 3, even steps of value and a
    /// 2.2 gamma curve bunched at the top, values down to about 80 looked close to full (64 the
    /// first clearly dimmer), and a geometric run from 80 down looked close to even (test 17); the
    /// curve as built was seen to dim and brighten predictably as an encoder turned (test 18). The
    /// dimming is continuous, so turning a control has a visible, proportional effect; it isn't
    /// meant for reading a level off the light (Adam, 2026-11-02).
    public static func brightness(position: Double, floor: Double = dimmestValue / 127) -> Double? {
        guard position.isFinite, FaderCurve.gainDB(position: position) != nil else { return nil }
        let position = min(max(position, 0), 1)
        let floor = min(max(floor, 1e-3), 1)
        return floor * pow(1 / floor, position)
    }

    /// How far a color can dim and keep its hue: until its smallest lit part reaches
    /// `dimmestValue`, the lowest value seen as lit (test 18). Purple (16, 0, 127) stops at
    /// 5/16 of its brightness and orange (127, 40, 0) at 5/40, so their smaller parts don't go
    /// dark first and leave blue or red; red, white, and the other one-part or even colors dim
    /// all the way. At those floors purple and orange were seen to keep their hue beside blue and
    /// red of the same brightness (test 18).
    public static func dimmestFraction(_ rgb: RGB) -> Double {
        let lit = [rgb.red, rgb.green, rgb.blue].filter { $0 > 0 }
        guard let smallest = lit.min() else { return 1 }
        return min(dimmestValue / Double(smallest), 1)
    }

    /// A palette color dimmed for a fader position (`brightness(position:floor:)`, down to the
    /// color's `dimmestFraction`), as its exact RGB (`paletteRGB`), or dark at −oo. A color
    /// without an exact one stays undimmed.
    public static func shaded(_ color: UInt8, position: Double) -> LightColor {
        guard let rgb = paletteRGB[color] else {
            return brightness(position: position) == nil ? .palette(0) : .palette(color)
        }
        guard let fraction = brightness(position: position, floor: dimmestFraction(rgb)) else { return .palette(0) }
        return .rgb(rgb.scaled(fraction))
    }

    /// Whether any channel's PFL is on in TotalMix FX.
    static func anyPFL(_ hub: SurfaceHub) -> Bool {
        hub.mirror.channels.values.contains { $0.pfl }
    }

    /// The palette color for each of TotalMix FX's eight colors (1 white, 2 grey, 3 orange, 4 red,
    /// 5 blue, 6 green, 7 yellow, 8 pink; docs/TOTALMIX-OSC.md, test 7). White, grey, orange, red,
    /// yellow, and green are from the part of the palette seen on the device (test 4); blue (45)
    /// and purple for pink (49) are past it, chosen from the guide's picture (inference).
    public static let paletteForTotalMixColor: [Int: UInt8] = [
        1: 3,   // white
        2: 1,   // grey
        3: 9,   // orange
        4: 5,   // red
        5: 45,  // blue
        6: 21,  // green
        7: 13,  // yellow
        8: 49,  // pink, as purple (TotalMix FX draws it purple)
    ]

    /// The palette color for a strip: its TotalMix FX color; an output left white (TotalMix FX's
    /// default) by its kind instead, monitoring outputs green and sends blue, as on the
    /// Roto-Control. The by-kind colors are for output strips, which this driver doesn't show (its
    /// strips are always sources); send rows take their colors from `sendColor`.
    public static func color(for info: StripInfo?) -> UInt8 {
        guard let info else { return 0 }
        let white = info.color == nil || info.color == 1
        switch info.kind {
        case .monitoring where white: return paletteForTotalMixColor[6] ?? 21
        case .send where white: return paletteForTotalMixColor[5] ?? 45
        default: return info.color.flatMap { paletteForTotalMixColor[$0] } ?? paletteForTotalMixColor[1] ?? 3
        }
    }
}
