import Foundation

/// Splits a pasted block of several prompts into one prompt per job.
///
/// Prompts are separated by a line holding nothing but three or more dashes
/// (`---`), surrounding whitespace allowed. A dash run inside a line is left
/// alone, and so are `{a|b}` wildcard groups, which still resolve per prompt.
/// Blank segments — a leading or trailing separator, or two in a row — are
/// dropped.
enum PromptBatchSplitter {
    /// The prompts in `text`, trimmed. A field with no separator comes back as a
    /// single element (or none, if it is blank).
    static func split(_ text: String) -> [String] {
        var segments: [[Substring]] = [[]]
        // `\r\n` is a single Character in Swift, so split on `isNewline`, not "\n".
        for line in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            if isSeparator(line) {
                segments.append([])
            } else {
                segments[segments.count - 1].append(line)
            }
        }
        return segments
            .map { $0.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    /// True when `text` holds more than one prompt.
    static func isBatch(_ text: String) -> Bool {
        split(text).count > 1
    }

    private static func isSeparator(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 3 && trimmed.allSatisfy { $0 == "-" }
    }
}
