import Foundation

public extension Data {
    /// Attempts to decode data into a UTF-8 string representation.
    var utf8String: String? {
        String(data: self, encoding: .utf8)
    }

    /// Formats the raw data as a hexadecimal string.
    var hexEncodedString: String {
        map { String(format: "%02hhx", $0) }.joined()
    }
}
