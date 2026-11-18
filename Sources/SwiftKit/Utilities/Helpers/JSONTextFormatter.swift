import Foundation

/// Token-preserving JSON formatting shared by console diagnostics and the inspector UI.
///
/// Re-serializing JSON through `JSONSerialization` round-trips numbers through `Double`, which
/// turns `58210.4` into `58210.400000000001`. This formatter only inserts whitespace, so every
/// literal stays exactly as it appeared on the wire.
internal enum JSONTextFormatter {
    /// Returns displayable text for a body, pretty-printing JSON object and array documents.
    /// - Parameter data: The raw body bytes.
    /// - Returns: UTF-8 text, or `nil` when the body is not valid UTF-8.
    internal static func displayText(from data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") || trimmed.hasPrefix("[") else {
            return text
        }

        return prettyPrinted(trimmed) ?? text
    }

    /// Adds indentation and newlines to a JSON document without parsing or re-encoding its values.
    /// - Parameter text: A JSON object or array, with optional existing whitespace.
    /// - Returns: The formatted document, or `nil` when the structure is unbalanced.
    internal static func prettyPrinted(_ text: String) -> String? {
        let characters = Array(text)
        var output = ""
        var indentation = 0
        var depth = 0
        var inString = false
        var isEscaped = false
        var lastSignificant: Character?

        func newline() {
            output += "\n" + String(repeating: "  ", count: indentation)
        }

        func nextSignificant(after index: Int) -> Character? {
            var cursor = index
            while cursor < characters.count {
                let character = characters[cursor]
                if !character.isWhitespace {
                    return character
                }
                cursor += 1
            }
            return nil
        }

        for (index, character) in characters.enumerated() {
            if inString {
                output.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                    lastSignificant = character
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
                output.append(character)

            case "{", "[":
                depth += 1
                output.append(character)
                let closing: Character = character == "{" ? "}" : "]"
                if nextSignificant(after: index + 1) != closing {
                    indentation += 1
                    newline()
                }
                lastSignificant = character

            case "}", "]":
                depth -= 1
                guard depth >= 0 else { return nil }

                if lastSignificant != "{" && lastSignificant != "[" {
                    indentation = max(0, indentation - 1)
                    newline()
                }
                output.append(character)
                lastSignificant = character

            case ",":
                output.append(character)
                newline()

            case ":":
                output.append(": ")

            case " ", "\n", "\t", "\r":
                continue

            default:
                output.append(character)
                lastSignificant = character
            }
        }

        guard depth == 0, !inString else { return nil }
        return output
    }
}
