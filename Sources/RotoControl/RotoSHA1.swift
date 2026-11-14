import Foundation

/// SHA-1 (FIPS 180-4), written here so that the library needs nothing beyond Foundation and builds
/// on macOS, Linux, and Windows. It is used only to derive the hashes that name plugins and
/// parameters (`RotoHash.sha1(of:length:)`), never for security.
public enum RotoSHA1 {
    /// The 20-byte digest of `bytes`.
    public static func digest(_ bytes: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        // Padding: a 1 bit, 0 bits to 56 bytes modulo 64, then the length in bits, big-endian.
        var message = bytes
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        let bitLength = UInt64(bytes.count) &* 8
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8((bitLength >> UInt64(shift)) & 0xFF))
        }
        var w = [UInt32](repeating: 0, count: 80)
        for block in stride(from: 0, to: message.count, by: 64) {
            for t in 0..<16 {
                let i = block + t * 4
                w[t] = UInt32(message[i]) << 24 | UInt32(message[i + 1]) << 16
                    | UInt32(message[i + 2]) << 8 | UInt32(message[i + 3])
            }
            for t in 16..<80 {
                w[t] = rotateLeft(w[t - 3] ^ w[t - 8] ^ w[t - 14] ^ w[t - 16], 1)
            }
            var (a, b, c, d, e) = (h[0], h[1], h[2], h[3], h[4])
            for t in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch t {
                case 0..<20: f = (b & c) | (~b & d); k = 0x5A82_7999
                case 20..<40: f = b ^ c ^ d; k = 0x6ED9_EBA1
                case 40..<60: f = (b & c) | (b & d) | (c & d); k = 0x8F1B_BCDC
                default: f = b ^ c ^ d; k = 0xCA62_C1D6
                }
                let next = rotateLeft(a, 5) &+ f &+ e &+ k &+ w[t]
                e = d
                d = c
                c = rotateLeft(b, 30)
                b = a
                a = next
            }
            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
        }
        return h.flatMap { word in
            [UInt8(word >> 24), UInt8((word >> 16) & 0xFF), UInt8((word >> 8) & 0xFF), UInt8(word & 0xFF)]
        }
    }

    /// The 20-byte digest of a text's UTF-8 bytes.
    public static func digest(_ text: String) -> [UInt8] {
        digest(Array(text.utf8))
    }

    private static func rotateLeft(_ value: UInt32, _ count: UInt32) -> UInt32 {
        value << count | value >> (32 - count)
    }
}
