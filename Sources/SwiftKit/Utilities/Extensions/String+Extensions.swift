import Foundation

public extension String {
    /// Returns data representation encoded in UTF-8.
    var utf8Data: Data {
        Data(self.utf8)
    }

    /// Convenience property indicating if a trimmed string is empty.
    var isBlank: Bool {
        trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
