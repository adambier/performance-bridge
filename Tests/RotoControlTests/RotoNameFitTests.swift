import XCTest
@testable import RotoControl

final class RotoNameFitTests: XCTestCase {
    func testANameThatFitsIsLeftAlone() {
        XCTAssertEqual(RotoNameFit.fit("Delay Volume"), "Delay Volume")
        XCTAssertEqual(RotoNameFit.fit("F1 Resonance"), "F1 Resonance")
        XCTAssertEqual(RotoNameFit.fit(""), "")
    }

    func testAbbreviationsComeFirstTheLastWordFirst() {
        XCTAssertEqual(RotoNameFit.fit("Reverb Volume"), "Reverb Vol")
        XCTAssertEqual(RotoNameFit.fit("F1 Resonance", to: 11), "F1 Res")
        XCTAssertEqual(RotoNameFit.fit("Filter Envelope Amount"), "Filt Env Amt")
        XCTAssertEqual(RotoNameFit.fit("Oscillator Frequency"), "Osc Freq")
        XCTAssertEqual(RotoNameFit.fit("MASTER VOLUME X"), "MASTER Vol X")
    }

    func testThenSpacesThenVowelsThenTheEnd() {
        XCTAssertEqual(RotoNameFit.fit("Env VCA Release"), "EnvVCAReleas")
        XCTAssertEqual(RotoNameFit.fit("Inharmonicity"), "Inharmonicty")
        XCTAssertEqual(RotoNameFit.fit("Tape Saturation Amount"), "TapeStrtnAmt")
        XCTAssertEqual(RotoNameFit.fit("BCDFGHJKLMNPQRST"), "BCDFGHJKLMNP")
        XCTAssertEqual(RotoNameFit.fit("phaser mix depth"), "phsr mx dpth")
        for name in ["Voice Send Level", "Convolution Reverb Dry/Wet", "Layer A Osc1 Volume", "Linked Filter LFO Amount"] {
            XCTAssertLessThanOrEqual(RotoNameFit.fit(name).count, 12, name)
        }
    }

    func testANameThatFitsIsNotShortenedToMatchItsPage() {
        XCTAssertEqual(RotoNameFit.fit(["Chorus Mix", "Delay Volume", "Reverb Volume"], to: [12, 12, 12]),
                       ["Chorus Mix", "Delay Volume", "Reverb Vol"])
        XCTAssertEqual(RotoNameFit.fit(["Delay Volume", "Phaser Mix"], to: [12, 12]), ["Delay Volume", "Phaser Mix"])
        XCTAssertEqual(RotoNameFit.fit(["F1 Resonance", "F2 Resonance"], to: [11, 12]), ["F1 Res", "F2 Resonance"])
        XCTAssertEqual(RotoNameFit.fit(["P1 Brightness", "P1 Timbre", "P1 Time", "P1 Movement", "FXA Dry/Wet",
                                        "FXB Dry/Wet", "Delay Volume", "Reverb Volume"], to: Array(repeating: 12, count: 8)),
                       ["P1 Bright", "P1 Timbre", "P1 Time", "P1 Movement", "FXA Dry/Wet",
                        "FXB Dry/Wet", "Delay Volume", "Reverb Vol"])
    }

    func testAWordShortenedTwiceGetsOneShortForm() {
        // Alone, the second would need one vowel less ("SaturatinMix").
        XCTAssertEqual(RotoNameFit.fit("Saturation Mix"), "SaturatinMix")
        XCTAssertEqual(RotoNameFit.fit(["Tape Saturation Amount", "Saturation Mix"], to: [12, 12]),
                       ["TapeStrtnAmt", "Strtn Mix"])
    }
}
