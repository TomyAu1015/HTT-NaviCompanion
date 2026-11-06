// Auto-generated Obfuscated AES-256 Key
import Foundation

enum KeyConfig {
    static let mask: [UInt8] = [30, 254, 163, 97, 161, 146, 92, 85, 118, 17, 194, 164, 24, 126, 224, 82, 218, 189, 198, 123, 8, 163, 66, 144, 46, 148, 223, 181, 18, 87, 223, 120]
    static let obfuscated: [UInt8] = [182, 120, 3, 228, 16, 50, 190, 145, 187, 31, 61, 122, 103, 177, 109, 114, 203, 96, 0, 135, 106, 228, 210, 185, 45, 154, 176, 247, 221, 142, 192, 194]
    static var keyBytes: [UInt8] {
        zip(mask, obfuscated).map { $0 ^ $1 }
    }
}
