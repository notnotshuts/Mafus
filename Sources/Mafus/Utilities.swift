import Foundation
import CryptoKit

struct ImageHashes: Sendable {
    let md5: String, sha1: String, sha256: String, sha512: String
    var text: String { "MD5\n\(md5)\n\nSHA-1\n\(sha1)\n\nSHA-256\n\(sha256)\n\nSHA-512\n\(sha512)" }
    static func sha256File(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var hash = SHA256()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty { try Task.checkCancellation(); hash.update(data: data) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    static func calculate(_ url: URL) throws -> Self {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var md5 = Insecure.MD5(), sha1 = Insecure.SHA1(), sha256 = SHA256(), sha512 = SHA512()
        while let data = try handle.read(upToCount: 4 * 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            md5.update(data: data); sha1.update(data: data); sha256.update(data: data); sha512.update(data: data)
        }
        func hex<D: Sequence>(_ digest: D) -> String where D.Element == UInt8 { digest.map { String(format: "%02x", $0) }.joined() }
        return Self(md5: hex(md5.finalize()), sha1: hex(sha1.finalize()), sha256: hex(sha256.finalize()), sha512: hex(sha512.finalize()))
    }
}
