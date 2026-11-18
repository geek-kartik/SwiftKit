import Foundation

/// Builds the multi-line transaction block used by
/// ``NetworkConfiguration/LogVerbosity/verbose``.
///
/// Every line carries a `[HTTP]` gutter so the Xcode console can be filtered down to network
/// traffic with a single search term. Header names that commonly carry credentials are replaced
/// with `[REDACTED]`, and the assembled block is passed through ``DataMasker`` before it reaches
/// the logger.
internal enum NetworkLogFormatter {
    /// Request outcome that shapes the response section of the block.
    internal enum Outcome {
        case success
        case unacceptedStatus
        case failure(NetworkError)
    }

    private static let gutter = "[HTTP]"

    /// Formats a complete request/response transaction.
    /// - Parameters:
    ///   - request: The prepared `URLRequest`, including merged headers and body.
    ///   - response: The HTTP response when one was received.
    ///   - outcome: Whether the request succeeded, returned an unaccepted status, or failed.
    ///   - duration: Wall-clock duration of the transport call in seconds.
    ///   - maxBodyBytes: Maximum body bytes to include for each body.
    /// - Returns: A masked, multi-line diagnostic block.
    internal static func verboseEntry(
        request: URLRequest,
        response: NetworkResponse?,
        outcome: Outcome,
        duration: TimeInterval,
        maxBodyBytes: Int
    ) -> String {
        var lines: [String] = []

        let method = request.httpMethod ?? "GET"
        let url = request.url?.absoluteString ?? "unknown"
        lines.append("\(gutter) ┌─ \(method) \(url)")

        appendHeaders(request.allHTTPHeaderFields ?? [:], title: "Request headers", to: &lines)
        appendBody(request.httpBody, title: "Request body", maxBytes: maxBodyBytes, to: &lines)

        let durationText = HTTPStatusText.milliseconds(duration)
        let bytes = response.map { HTTPStatusText.byteCount($0.data.count) } ?? "0 B"

        switch outcome {
        case .success:
            if let response {
                lines.append(
                    "\(gutter) │ ← \(HTTPStatusText.statusLine(response.statusCode)) · \(durationText) · \(bytes)"
                )
                appendHeaders(response.headers, title: "Response headers", to: &lines)
                appendBody(response.data, title: "Response body", maxBytes: maxBodyBytes, to: &lines)
            }

        case .unacceptedStatus:
            if let response {
                lines.append(
                    "\(gutter) │ ✖ \(HTTPStatusText.statusLine(response.statusCode)) · \(durationText) · \(bytes)"
                )
                appendHeaders(response.headers, title: "Response headers", to: &lines)
                appendBody(response.data, title: "Response body", maxBytes: maxBodyBytes, to: &lines)
            }

        case .failure(let error):
            lines.append("\(gutter) │ ✖ Failed · \(error.logDescription) · \(durationText)")
            if let description = error.errorDescription {
                lines.append("\(gutter) │   \(description)")
            }
            if let response {
                lines.append("\(gutter) │   Response · \(HTTPStatusText.statusLine(response.statusCode)) · \(bytes)")
            }
        }

        lines.append("\(gutter) └─")
        return DataMasker.mask(lines.joined(separator: "\n"))
    }

    /// Splits a formatted block into chunks that stay below Apple's per-message log limit.
    ///
    /// `os_log` truncates messages longer than roughly 1 KB, which would cut off response
    /// bodies. Splitting on line boundaries keeps every JSON line intact while guaranteeing
    /// the complete transaction reaches the console. The limit is measured in UTF-8 bytes
    /// because box-drawing and bullet characters occupy three bytes each.
    /// - Parameters:
    ///   - message: The formatted block.
    ///   - limit: Maximum UTF-8 bytes per chunk.
    /// - Returns: One or more chunks, each at most `limit` bytes.
    internal static func chunks(of message: String, limit: Int = 800) -> [String] {
        let safeLimit = max(120, limit)
        guard message.utf8.count > safeLimit else { return [message] }

        var chunks: [String] = []
        var current = ""

        func flush() {
            guard !current.isEmpty else { return }
            chunks.append(current)
            current = ""
        }

        func append(_ line: String) {
            let separator = current.isEmpty ? 0 : 1
            if current.utf8.count + separator + line.utf8.count <= safeLimit {
                if !current.isEmpty {
                    current += "\n"
                }
                current += line
                return
            }

            flush()

            var remainder = line
            while remainder.utf8.count > safeLimit {
                var piece = ""
                for character in remainder {
                    let width = String(character).utf8.count
                    if piece.utf8.count + width > safeLimit {
                        break
                    }
                    piece.append(character)
                }

                guard !piece.isEmpty else { break }
                chunks.append(piece)
                remainder = String(remainder.dropFirst(piece.count))
            }

            current = remainder
        }

        for line in message.split(separator: "\n", omittingEmptySubsequences: false) {
            append(String(line))
        }

        flush()
        return chunks
    }

    // MARK: - Sections

    private static func appendHeaders(
        _ headers: [String: String],
        title: String,
        to lines: inout [String]
    ) {
        guard !headers.isEmpty else { return }

        lines.append("\(gutter) │ \(title)")
        for (name, value) in headers.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
            let shown = SensitiveHeaders.isSensitive(name) ? "[REDACTED]" : value
            lines.append("\(gutter) │   \(name): \(shown)")
        }
    }

    private static func appendBody(
        _ data: Data?,
        title: String,
        maxBytes: Int,
        to lines: inout [String]
    ) {
        guard let data, !data.isEmpty else { return }

        let total = data.count
        let allowed = max(0, maxBytes)
        let clipped = data.prefix(allowed)
        let truncated = clipped.count < total

        var caption = "\(gutter) │ \(title) · \(HTTPStatusText.byteCount(total))"
        if truncated {
            caption += " · showing first \(clipped.count) bytes"
        }
        lines.append(caption)

        guard allowed > 0, !clipped.isEmpty else { return }

        if let text = JSONTextFormatter.displayText(from: clipped) {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("\(gutter) │   \(line)")
            }
        } else {
            lines.append("\(gutter) │   <binary \(clipped.count) bytes>")
        }
    }
}
