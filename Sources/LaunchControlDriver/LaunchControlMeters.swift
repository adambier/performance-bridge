// Meters on a Launch Control's home screen (Adam, 2026-11-10): with `showsMeters` on, the
// stationary display is a picture (SysEx 09h, target 35h; docs/LAUNCH-CONTROL-XL3.md, test 21)
// with the page line at the top and a meter for each of the page's eight strips below it, two bars
// for a stereo channel. A new picture goes out only after the device's ready reply (or
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
#if canImport(OXIE16)
import OXIE16
#endif

extension LaunchControlDriver {
    /// The bitmap target for the stationary display: 35h, as "Configure displays" numbers it (the
    /// guide's bitmap section says 20h, which drew nothing; docs/LAUNCH-CONTROL-XL3.md, test 21).
    public static let bitmapTarget: UInt8 = 0x35
    /// How long to wait for the ready reply before sending the next picture anyway, in seconds.
    /// Replies took 66–72 ms, once 340 ms while a control moved (test 21).
    public static let bitmapTimeout = 0.5
    /// The first pixel row of the meters, under the page line (7 pixels tall, then 3 blank).
    public static let meterTop = 10
    /// The meters' height in pixels, from `meterTop` to the screen's bottom row.
    public static let meterHeight = LaunchControlBitmap.height - meterTop
    /// Levels marked with a dotted line behind the bars, in dBFS: TotalMix FX's own channel-strip
    /// marks (docs/TOTALMIX-OSC.md, "Meter colors"); a starting choice, to try on the device.
    public static let meterMarks: [Double] = [-6, -20, -40]
    /// The time constant of the average the bars follow, in seconds (the E16's, `E16Driver.meterAverage`).
    public static let meterAverage = 0.03
    /// How far below the averaged peaks a bar sits, in dB (the E16's, `E16Driver.meterOffset`).
    public static let meterOffset = 6.0
    /// How long a peak holds before it drops to the level, in seconds (the E16's, `E16Driver.peakHold`).
    public static let peakHold = 2.0

    /// Turns `showsMeters` on or off, and returns what changes on the device: with meters off, the
    /// text home screen is drawn again (that it then shows instead of the last picture is an
    /// inference, to check on the device); with meters on, `tick` draws the picture.
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
        let title = Self.withPage(pageTitle(hub: hub), pageNumber: pageNumber) {
            E16Screen.width(of: $0.uppercased()) <= LaunchControlBitmap.width
        }
        var levels: [[Int]] = [], peaks: [[Int]] = []
        let strips = stripInfos
        for info in strips {
            guard let info else { levels.append([]); peaks.append([]); continue }
            var refs = [info.channel]
            if info.stereo { refs.append(ChannelRef(info.channel.bus, info.channel.channel + 1)) }
            levels.append(refs.map { averagedHeight($0, hub: hub, now: now) })
            peaks.append(refs.map { heldPeak($0, hub: hub, now: now) })
        }
        let picture = Self.meterPicture(title: title, levels: levels, peaks: peaks)
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

    /// The home screen as a picture: `title` (in capitals) at the top, then one 16-pixel column
    /// per strip, left to right, with one bar 12 pixels wide for a mono channel or two 6 pixels wide
    /// for a stereo one (`levels` and `peaks` give one or two heights per strip, empty for no
    /// channel), each with its held peak as a line, over dotted lines at `meterMarks`.
    public static func meterPicture(title: String, levels: [[Int]], peaks: [[Int]]) -> LaunchControlBitmap {
        var text = E16Screen()
        _ = text.draw(title.uppercased(), x: 0, y: 0)
        var picture = LaunchControlBitmap()
        for y in 0..<E16Font.glyphHeight {
            for x in 0..<LaunchControlBitmap.width where text.pixel(x, y) { picture[x, y] = true }
        }
        let bottom = LaunchControlBitmap.height - 1
        for mark in meterMarks {
            let y = bottom - meterHeight(db: mark) + 1
            for x in stride(from: 0, to: LaunchControlBitmap.width, by: 4) { picture[x, y] = true }
        }
        for (column, heights) in levels.enumerated() {
            let left = column * 16
            let bars: [(x: Int, width: Int)] = heights.count > 1 ? [(left + 1, 6), (left + 9, 6)] : [(left + 2, 12)]
            for (bar, (x, width)) in zip(bars.indices, bars) where heights.indices.contains(bar) {
                // Clear the bar's column first, so the dotted marks show only between bars.
                picture.fill(x: x, y: meterTop, width: width, height: meterHeight, false)
                let height = min(max(heights[bar], 0), meterHeight)
                picture.fill(x: x, y: bottom - height + 1, width: width, height: height)
                let peaksHere = peaks.indices.contains(column) ? peaks[column] : []
                if peaksHere.indices.contains(bar), peaksHere[bar] > height, peaksHere[bar] > 0 {
                    picture.fill(x: x, y: bottom - min(peaksHere[bar], meterHeight) + 1, width: width, height: 1)
                }
            }
        }
        return picture
    }
}
