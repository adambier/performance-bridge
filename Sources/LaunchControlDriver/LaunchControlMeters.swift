// Meters on a Launch Control's home screen (Adam, 2026-11-10): with `showsMeters` on, the
// stationary display is a picture (SysEx 09h, target 35h; docs/LAUNCH-CONTROL-XL3.md, test 21):
// a meter for each of the page's eight strips, the screen's full height, two bars for a stereo
// channel, each bar with its held peak. On the device (Adam, 2026-11-10), dB ticks between the
// strips read as a grid, with or without the peaks, so there are none; and with equal gaps
// everywhere a stereo pair's two bars couldn't be told from two strips, so a pair's bars are one
// pixel apart and the strips five. A page line in the E16's font was too small to read on the XL 3's screen (Adam,
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
    /// The first pixel row of the meters: the top, since the picture has no page line.
    public static let meterTop = 0
    /// The meters' height in pixels, from `meterTop` to the screen's bottom row.
    public static let meterHeight = LaunchControlBitmap.height - meterTop
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
        var levels: [[Int]] = [], peaks: [[Int]] = []
        for info in stripInfos {
            guard let info else { levels.append([]); peaks.append([]); continue }
            var refs = [info.channel]
            if info.stereo { refs.append(ChannelRef(info.channel.bus, info.channel.channel + 1)) }
            levels.append(refs.map { averagedHeight($0, hub: hub, now: now) })
            peaks.append(refs.map { heldPeak($0, hub: hub, now: now) })
        }
        let picture = Self.meterPicture(levels: levels, peaks: peaks)
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

    private mutating func heldPeak(_ ref: ChannelRef, hub: SurfaceHub, now: Double) -> Int {
        let height = Self.meterHeight(db: hub.mirror.meters[ref] ?? -.infinity)
        if let held = meterPeaks[ref], held.height >= height, now - held.at < Self.peakHold { return held.height }
        meterPeaks[ref] = (height, now)
        return height
    }

    /// The home screen as a picture: one 16-pixel column per strip, left to right, each with a meter
    /// 11 pixels wide (x + 2 to x + 12), so five dark pixels separate the strips: one bar for a mono
    /// channel, or two bars 5 pixels wide and one pixel apart for a stereo one (`levels` and `peaks`
    /// give one or two heights per strip, empty for no channel), each with its held peak as a line.
    public static func meterPicture(levels: [[Int]], peaks: [[Int]]) -> LaunchControlBitmap {
        var picture = LaunchControlBitmap()
        let bottom = LaunchControlBitmap.height - 1
        for (column, heights) in levels.enumerated() {
            let left = column * 16
            let bars: [(x: Int, width: Int)] = heights.count > 1 ? [(left + 2, 5), (left + 8, 5)] : [(left + 2, 11)]
            let peaksHere = peaks.indices.contains(column) ? peaks[column] : []
            for (bar, (x, width)) in zip(bars.indices, bars) where heights.indices.contains(bar) {
                let height = min(max(heights[bar], 0), meterHeight)
                picture.fill(x: x, y: bottom - height + 1, width: width, height: height)
                if peaksHere.indices.contains(bar), peaksHere[bar] > height {
                    picture.fill(x: x, y: bottom - min(peaksHere[bar], meterHeight) + 1, width: width, height: 1)
                }
            }
        }
        return picture
    }
}
