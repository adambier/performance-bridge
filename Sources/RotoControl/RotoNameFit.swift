import Foundation

/// Shortens names to fit the Roto-Control's 12-character name fields, by the first of these that
/// is enough: abbreviating words, the last first; closing up spaces before a capital or a digit;
/// dropping lowercase vowels from the longest word, its last first, never a word's first letter;
/// and at last cutting the end off.
///
/// The abbreviations are the short forms Arturia's own parameter names use, without a period, as
/// most of them are written there (counted over the parameter names of the instruments installed
/// on Adam's Mac, 2026-11-14: e.g., "Vol" 16 times and "Vol." never, "Freq" 1,378 times and
/// "Freq." 4). A word Arturia never shortens (e.g., "Level", "Attack", "Delay") has none.
public enum RotoNameFit {
    /// A word, in lowercase, and its short form.
    public static let abbreviations: [String: String] = [
        "volume": "Vol", "resonance": "Res", "frequency": "Freq", "amount": "Amt", "envelope": "Env",
        "oscillator": "Osc", "modulation": "Mod", "feedback": "FB", "distortion": "Dist", "velocity": "Velo",
        "keyboard": "Kbd", "waveform": "Wave", "compressor": "Comp", "threshold": "Thresh", "sensitivity": "Sens",
        "brightness": "Bright", "octave": "Oct", "sequencer": "Seq", "arpeggiator": "Arp", "amplitude": "Amp",
        "amplifier": "Amp", "harmonic": "Harm", "harmonics": "Harm", "trigger": "Trig", "polyphony": "Poly",
        "portamento": "Porta", "semitone": "Semi", "position": "Pos", "sustain": "Sus", "vibrato": "Vib",
        "unison": "Uni", "reverb": "Rev", "cutoff": "Cut", "parameter": "Param", "filter": "Filt",
        "input": "In", "output": "Out", "low": "Lo", "high": "Hi",
    ]

    /// One name, fitted to `length` characters.
    public static func fit(_ name: String, to length: Int = RotoSysEx.nameFieldLength - 1) -> String {
        fit([name], to: [length])[0]
    }

    /// The names of one page, each fitted to its length. A word abbreviated in one name is
    /// abbreviated in all of them, so that a page doesn't read "Delay Volume" beside "Reverb Vol".
    public static func fit(_ names: [String], to lengths: [Int]) -> [String] {
        var used: Set<String> = []
        for (name, length) in zip(names, lengths) {
            var words = name.split(separator: " ").map(String.init)
            var index = words.count - 1
            while joined(words).count > length, index >= 0 {
                if let short = abbreviations[words[index].lowercased()] {
                    used.insert(words[index].lowercased())
                    words[index] = short
                }
                index -= 1
            }
        }
        return zip(names, lengths).map { name, length in
            var words = name.split(separator: " ").map(String.init)
            for index in words.indices {
                if used.contains(words[index].lowercased()), let short = abbreviations[words[index].lowercased()] { words[index] = short }
            }
            return squeeze(words, to: max(length, 0))
        }
    }

    private static func joined(_ words: [String]) -> String { words.joined(separator: " ") }

    /// Closes up spaces, then drops vowels, then cuts.
    private static func squeeze(_ words: [String], to length: Int) -> String {
        var words = words
        guard !words.isEmpty else { return "" }
        // Whether a space stands before each word after the first.
        var spaces = [Bool](repeating: true, count: words.count)
        func text() -> String {
            var result = words[0]
            for index in 1..<words.count { result += (spaces[index] ? " " : "") + words[index] }
            return result
        }
        if text().count <= length { return text() }
        for index in stride(from: words.count - 1, to: 0, by: -1) {
            guard let first = words[index].first, first.isUppercase || first.isNumber,
                  let last = words[index - 1].last, last.isLetter || last.isNumber else { continue }
            spaces[index] = false
            if text().count <= length { return text() }
        }
        let vowels: Set<Character> = ["a", "e", "i", "o", "u"]
        while text().count > length {
            // The longest word that still has a vowel to give; of equals, the last.
            var best: (word: Int, at: String.Index)?
            for index in words.indices {
                let word = words[index]
                guard let at = word.indices.dropFirst().last(where: { vowels.contains(word[$0]) }) else { continue }
                if best == nil || word.count >= words[best!.word].count { best = (index, at) }
            }
            guard let drop = best else { break }
            words[drop.word].remove(at: drop.at)
        }
        return String(text().prefix(length))
    }
}
