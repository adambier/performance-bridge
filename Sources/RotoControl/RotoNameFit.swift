import Foundation

/// Shortens names to fit the Roto-Control's 12-character name fields, by the first of these that
/// is enough: abbreviating words, the last first; closing up spaces before a capital or a digit;
/// dropping lowercase vowels from the longest word, its last first, never a word's first letter;
/// shortening the longest word from its end; and at last cutting the end off. An abbreviated word
/// is left as it is by the later steps.
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

    /// The names of one page, each fitted to its length. A name that fits is left whole, even
    /// where a word in it is shortened in another name (Adam, 2026-11-15). A word shortened in more
    /// than one name gets one short form in all of them: the shortest any of them needed.
    public static func fit(_ names: [String], to lengths: [Int]) -> [String] {
        var shared: [String: String] = [:]
        var fitted: [String] = []
        // A few passes settle the shared short forms.
        for _ in 0..<4 {
            var found: [String: String] = [:]
            fitted = zip(names, lengths).map { name, length in
                fitOne(name, to: max(length, 0), shared: shared, found: &found)
            }
            if found == shared { break }
            shared = found
        }
        return fitted
    }

    /// One name, shortened only as much as it needs, using a page's shared short forms first.
    /// Each word it shortens goes into `found`, keeping the shorter of two forms.
    private static func fitOne(_ name: String, to length: Int, shared: [String: String],
                               found: inout [String: String]) -> String {
        let original = name.split(separator: " ").map(String.init)
        guard !original.isEmpty, joined(original).count > length else { return joined(original) }
        var words = original
        // An abbreviation from the list is final: it loses no letters afterward (Adam, 2026-11-15).
        var fixed = [Bool](repeating: false, count: words.count)
        var index = words.count - 1
        while joined(words).count > length, index >= 0 {
            let key = words[index].lowercased()
            if let short = abbreviations[key] {
                words[index] = short
                fixed[index] = true
            } else if let short = shared[key] {
                words[index] = short
            }
            index -= 1
        }
        let text = squeeze(&words, fixed: fixed, to: length)
        for (before, after) in zip(original, words) where before != after {
            let key = before.lowercased()
            if let known = found[key], known.count <= after.count { continue }
            found[key] = after
        }
        return text
    }

    private static func joined(_ words: [String]) -> String { words.joined(separator: " ") }

    /// Closes up spaces, then drops vowels, then shortens the longest word from its end, leaving
    /// `fixed` words as they are, and cuts only if that is not enough. `words` keeps what was dropped.
    private static func squeeze(_ words: inout [String], fixed: [Bool], to length: Int) -> String {
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
            for index in words.indices where !fixed[index] {
                let word = words[index]
                guard let at = word.indices.dropFirst().last(where: { vowels.contains(word[$0]) }) else { continue }
                if best == nil || word.count >= words[best!.word].count { best = (index, at) }
            }
            guard let drop = best else { break }
            words[drop.word].remove(at: drop.at)
        }
        while text().count > length {
            // The longest word that is not an abbreviation; of equals, the last.
            var longest: Int?
            for index in words.indices where !fixed[index] && words[index].count > 1 {
                if longest == nil || words[index].count >= words[longest!].count { longest = index }
            }
            guard let trim = longest else { break }
            words[trim].removeLast()
        }
        return String(text().prefix(length))
    }
}
