// Meters on a Launch Control's home screen (Adam, 2026-11-10): with `showsMeters` on, the
// stationary display is a picture (SysEx 09h, target 35h; docs/LAUNCH-CONTROL-XL3.md, test 21):
// a meter for each of the page's eight strips, the screen's full height, two bars for a stereo
// channel, each bar with its held peak, and the channel's number under it. On the device (Adam,
// 2026-11-10), dB ticks between the strips read as a grid, with or without the peaks, so there
// are none (marks at the screen's side were declined too); with equal gaps everywhere a stereo
// pair's two bars couldn't be told from two strips, so a pair's bars are one pixel apart and the
// strips five; and a peak line with no bar under it, at a channel's noise floor, looked like stray
// pixels, so a peak shows only over a bar.
//
// The numbers count each kind in the channel order, as the text home screen's first line does
// ("In 1-3, PB 1-3" gives 1 2 3 1 2 3), with one line under each run of playbacks (Adam,
// 2026-11-10: drawn in reverse they were unreadable in a mockup, a one-pixel underline under each
// number read as part of the digit on the device, a line under each run read clearly, a line
// above the numbers was tried and moved back). The screen's bottom row stays dark: at an angle
// it is hard to read (Adam, 2026-11-10). Whether this numbering is intuitive next to TotalMix
// FX's own channel numbers is for the UI review (Adam, 2026-11-10). A page line in the E16's font was too small to read on the XL 3's screen (Adam,
// 2026-11-10), so Track shows the page in the device's own text instead (`goToPage`). A new picture goes out only after the device's ready reply (or
// `bitmapTimeout` without one), and only when it changed. A control's own temporary display shows
// over the picture as usual (test 21), so the send rows' outputs still show on Page (the overlay)
// and when an encoder turns.
//
// The averaging and peak hold are the E16's, tuned there by eye against TotalMix FX's own meters
// (docs/OXI-E16.md, section 5); the scale is `MeterScale`, shared with the Roto-Control and the E16.

import Foundation
#if canImport(SurfaceCore)
import SurfaceCore
#endif
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif
#if canImport(LaunchControl)
import LaunchControl
#endif

extension LaunchControlDriver {
    /// The bitmap target for the stationary display: 35h, as "Configure displays" numbers it (the
    /// guide's bitmap section says 20h, which drew nothing; docs/LAUNCH-CONTROL-XL3.md, test 21).
    public static let bitmapTarget: UInt8 = 0x35
    /// How long to wait for the ready reply before sending the next picture anyway, in seconds.
    /// Replies took 66–72 ms, once 340 ms while a control moved (test 21).
    public static let bitmapTimeout = 0.5
    /// The meters' height in pixels, from the screen's top row; the channel numbers go below.
    public static let meterHeight = 45
    /// The top row of the channel numbers: three dark rows below the meters (Adam, 2026-11-10: one
    /// more than the first try), 11 rows tall.
    static let numberTop = 48
    /// The top row of the line under the playbacks' numbers: two dark rows below them, two rows
    /// tall, leaving the screen's bottom row dark.
    static let playbackLineTop = 61
    /// The time constant of the average the bars follow, in seconds (the E16's, `E16Driver.meterAverage`).
    public static let meterAverage = 0.03
    /// How far below the averaged peaks a bar sits, in dB (the E16's, `E16Driver.meterOffset`).
    public static let meterOffset = 6.0
    /// How long a peak holds before it drops to the level, in seconds (the E16's, `E16Driver.peakHold`).
    public static let peakHold = 2.0

    /// Turns `showsMeters` on or off, and returns what changes on the device: with meters off, the
    /// text home screen is drawn again, and shows in place of the last picture
    /// (docs/LAUNCH-CONTROL-XL3.md, test 22); with meters on, `tick` draws the picture.
    public mutating func setShowsMeters(_ on: Bool, hub: SurfaceHub) -> [UInt8] {
        guard on != showsMeters else { return [] }
        showsMeters = on
        shownBitmap = nil
        bitmapSentAt = nil
        guard isConnected, !on else { return [] }
        forgetStationaryText()
        return drawStationary(hub: hub)
    }

    /// The picture for now, if it changed and the device is ready for one.
    mutating func drawMeterScreen(hub: SurfaceHub, now: Double) -> [UInt8] {
        if let sent = bitmapSentAt, now - sent < Self.bitmapTimeout { return [] }
        var levels: [[Int]] = [], peaks: [[Int]] = [], numbers: [MeterNumber?] = []
        let order = hub.layout.channels(.sources, in: hub.mirror)
        for info in stripInfos {
            guard let info else { levels.append([]); peaks.append([]); numbers.append(nil); continue }
            numbers.append(Self.meterNumber(info.channel, order: order))
            var refs = [info.channel]
            if info.stereo { refs.append(ChannelRef(info.channel.bus, info.channel.channel + 1)) }
            levels.append(refs.map { averagedHeight($0, hub: hub, now: now) })
            peaks.append(refs.map { heldPeak($0, hub: hub, now: now) })
        }
        let picture = Self.meterPicture(levels: levels, peaks: peaks, numbers: numbers)
        let packed = picture.packed
        guard packed != shownBitmap else { return [] }
        shownBitmap = packed
        bitmapSentAt = now
        return LaunchControlOutgoing.bitmap(picture, target: Self.bitmapTarget, model: device)
    }

    /// A level as a bar height on `MeterScale`.
    static func meterHeight(db: Double) -> Int {
        Int((Double(MeterScale.value(peakDB: db)) / Double(MeterScale.fullScale) * Double(meterHeight)).rounded())
    }

    private mutating func averagedHeight(_ ref: ChannelRef, hub: SurfaceHub, now: Double) -> Int {
        let db = hub.mirror.meters[ref] ?? -.infinity
        let power = db.isFinite ? pow(10, db / 10) : 0
        var average = meterAverages[ref] ?? (power, now)
        let dt = max(now - average.at, 0)
        average.power += (power - average.power) * (1 - exp(-dt / Self.meterAverage))
        average.at = now
        meterAverages[ref] = average
        return average.power > 0 ? Self.meterHeight(db: 10 * log10(average.power) - Self.meterOffset) : 0
    }

    /// A strip's number under its meter: the channel's place among its kind in `order`, as the
    /// text home screen counts (`pageTitle`), marked for a playback.
    static func meterNumber(_ channel: ChannelRef, order: [ChannelRef]) -> MeterNumber? {
        guard let index = order.filter({ $0.bus == channel.bus }).firstIndex(of: channel) else { return nil }
        return MeterNumber(number: index + 1, marked: channel.bus == .playback)
    }

    private mutating func heldPeak(_ ref: ChannelRef, hub: SurfaceHub, now: Double) -> Int {
        let height = Self.meterHeight(db: hub.mirror.meters[ref] ?? -.infinity)
        if let held = meterPeaks[ref], held.height >= height, now - held.at < Self.peakHold { return held.height }
        meterPeaks[ref] = (height, now)
        return height
    }

    /// A number under a meter, and whether it is marked (a playback's): one line runs under each
    /// run of marked numbers.
    public struct MeterNumber: Equatable, Sendable {
        /// The number, from 1.
        public var number: Int
        /// Whether the line under the playbacks runs under it.
        public var marked: Bool
        /// A number, marked or not.
        public init(number: Int, marked: Bool) {
            self.number = number
            self.marked = marked
        }
    }

    /// The digits for the channel numbers, 6 × 11 pixels with two-pixel strokes, about as tall as
    /// the device's own text. The project's own drawing.
    static let digits: [[String]] = [
        [".####.", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."],
        ["...##.", "..###.", ".####.", "...##.", "...##.", "...##.", "...##.", "...##.", "...##.", "...##.", "...##."],
        [".####.", "##..##", "....##", "....##", "...##.", "..##..", ".##...", "##....", "##....", "##....", "######"],
        [".####.", "##..##", "....##", "....##", "..###.", "....##", "....##", "....##", "....##", "##..##", ".####."],
        ["...##.", "..###.", ".####.", "##.##.", "##.##.", "##.##.", "######", "...##.", "...##.", "...##.", "...##."],
        ["######", "##....", "##....", "##....", "#####.", "....##", "....##", "....##", "....##", "##..##", ".####."],
        [".####.", "##..##", "##....", "##....", "#####.", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."],
        ["######", "....##", "....##", "...##.", "...##.", "..##..", "..##..", ".##...", ".##...", ".##...", ".##..."],
        [".####.", "##..##", "##..##", "##..##", ".####.", "##..##", "##..##", "##..##", "##..##", "##..##", ".####."],
        [".####.", "##..##", "##..##", "##..##", "##..##", ".#####", "....##", "....##", "....##", "##..##", ".####."],
    ]

    /// Draws `number` centered under the meter of the strip starting at `left`: digits 6 pixels
    /// wide one pixel apart, or, for three digits, 4 pixels wide (each digit's second and fifth
    /// columns left out), so a number stays inside its 16-pixel column.
    static func drawNumber(_ number: MeterNumber, left: Int, in picture: inout LaunchControlBitmap) {
        let text = String(number.number).compactMap { $0.wholeNumberValue }
        let columns = text.count > 2 ? [0, 2, 3, 5] : Array(0..<6)
        let width = text.count * columns.count + text.count - 1
        let x0 = left + 2 + (11 - width) / 2
        for (place, digit) in text.enumerated() {
            for (row, line) in digits[digit].enumerated() {
                let pixels = Array(line)
                for (offset, column) in columns.enumerated() where pixels[column] == "#" {
                    picture[x0 + place * (columns.count + 1) + offset, numberTop + row] = true
                }
            }
        }
    }

    /// The home screen as a picture: one 16-pixel column per strip, left to right, each with a meter
    /// 11 pixels wide (x + 2 to x + 12), so five dark pixels separate the strips: one bar for a mono
    /// channel, or two bars 5 pixels wide and one pixel apart for a stereo one (`levels` and `peaks`
    /// give one or two heights per strip, empty for no channel), each with its held peak as a line
    /// while the bar shows; the strip's number under it (`numbers`, `nil` for none); and a line
    /// under each run of marked numbers, from the first one's meter to the last one's. A page with
    /// fewer than eight strips is centered (Adam, 2026-11-10): the screen sits to the left of the
    /// controls, so a meter's place never lined up with its fader anyway (seen in Adam's photos).
    public static func meterPicture(levels: [[Int]], peaks: [[Int]], numbers: [MeterNumber?] = []) -> LaunchControlBitmap {
        var picture = LaunchControlBitmap()
        let bottom = meterHeight - 1
        let used = (0..<max(levels.count, numbers.count)).last {
            (levels.indices.contains($0) && !levels[$0].isEmpty) || (numbers.indices.contains($0) && numbers[$0] != nil)
        }.map { $0 + 1 } ?? 0
        let shift = (stripCount - min(used, stripCount)) * 8
        for (column, number) in numbers.enumerated() {
            guard let number else { continue }
            drawNumber(number, left: shift + column * 16, in: &picture)
            guard number.marked else { continue }
            let joinsLeft = column > 0 && numbers[column - 1]?.marked == true
            picture.fill(x: shift + column * 16 + (joinsLeft ? -3 : 2), y: playbackLineTop, width: joinsLeft ? 16 : 11, height: 2)
        }
        for (column, heights) in levels.enumerated() {
            let left = shift + column * 16
            let bars: [(x: Int, width: Int)] = heights.count > 1 ? [(left + 2, 5), (left + 8, 5)] : [(left + 2, 11)]
            let peaksHere = peaks.indices.contains(column) ? peaks[column] : []
            for (bar, (x, width)) in zip(bars.indices, bars) where heights.indices.contains(bar) {
                let height = min(max(heights[bar], 0), meterHeight)
                picture.fill(x: x, y: bottom - height + 1, width: width, height: height)
                if height > 0, peaksHere.indices.contains(bar), peaksHere[bar] > height {
                    picture.fill(x: x, y: bottom - min(peaksHere[bar], meterHeight) + 1, width: width, height: 1)
                }
            }
        }
        return picture
    }
}
