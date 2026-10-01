import Foundation

/// An inline `@aspect W:H` line in a prompt: a per-prompt aspect override for the
/// job it queues, written by scenario tools so each prompt in a `---` batch can
/// carry its own frame.
///
/// The override is silent: it sizes the job, never the dimension picker, so the
/// user's own width and height survive the queue press. The directive must sit on
/// a line of its own (`@aspect 3:2`, `@aspect 16x9`, any case); the line is always
/// stripped from the prompt, and when several are present the last one wins.
enum AspectDirective {
    /// `prompt` with every `@aspect` line removed, and the ratio (width ÷ height)
    /// the last well-formed one asked for — nil when there is none.
    static func extract(from prompt: String) -> (prompt: String, ratio: Double?) {
        var ratio: Double?
        var found = false
        var kept: [Substring] = []
        // `\r\n` is a single Character in Swift, so split on `isNewline`, not "\n".
        for line in prompt.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            guard let argument = argument(of: line) else {
                kept.append(line)
                continue
            }
            found = true
            if let parsed = parseRatio(argument) {
                ratio = parsed
            }
        }
        guard found else { return (prompt, nil) }
        return (kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines), ratio)
    }

    /// The job size for `ratio`, snapped from the GUI's current `width` × `height`.
    ///
    /// The GUI's area is the target, so a draft-size or rapid-iteration setting
    /// carries over instead of jumping to the preset default. When the GUI already
    /// sits at the requested ratio its size is used as-is. Nil when `ratio` is nil.
    static func size(
        ratio: Double?,
        width: Int,
        height: Int,
        constraints: DimensionConstraints
    ) -> (width: Int, height: Int)? {
        guard let ratio, width > 0, height > 0 else { return nil }
        let current = Double(width) / Double(height)
        if abs(current - ratio) / ratio < 0.005 {
            return (width, height)
        }
        let megapixels = Double(width * height) / 1_000_000
        return constraints.dimensions(ratio: ratio, megapixels: megapixels)
    }

    /// The text after `@aspect` when `line` is a directive line.
    private static func argument(of line: Substring) -> Substring? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let keyword = "@aspect"
        guard trimmed.lowercased().hasPrefix(keyword) else { return nil }
        let rest = trimmed.dropFirst(keyword.count)
        // `@aspectual` is not a directive.
        guard rest.isEmpty || rest.first?.isWhitespace == true || rest.first == "=" || rest.first == ":" else {
            return nil
        }
        return Substring(rest.drop { $0.isWhitespace || $0 == "=" || $0 == ":" })
    }

    /// `3:2`, `16x9`, `2.39:1` → width ÷ height. Nil for anything else.
    private static func parseRatio(_ text: Substring) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces)
            .lowercased()
            .split { $0 == ":" || $0 == "x" || $0 == "/" }
        guard parts.count == 2,
              let w = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let h = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              w.isFinite, h.isFinite, w > 0, h > 0
        else { return nil }
        return w / h
    }
}
