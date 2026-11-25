import Foundation

/// A vowel drawn out in the middle of a word, as lyrics write what is
/// sung: みなさーん, すご〜い, みなさー ん. The mark cuts the word in
/// two before the dictionary sees it, and the pieces are read as other
/// words (のみ + な + さー + ん). So the line is also analyzed with the
/// marks taken out, and where a word then runs over the place a mark
/// was, that word is taken, with the long vowel put back in its reading.
enum DrawnOutVowels {
    private static let marks: Set<Character> = ["ー", "ｰ", "〜", "～", "~"]

    private static func isHiragana(_ ch: Character) -> Bool {
        guard let c = ch.unicodeScalars.first else { return false }
        return c.value >= 0x3041 && c.value <= 0x3096
    }

    /// A run of marks between two hiragana, with the blank after it.
    private struct Site {
        /// The marks, in characters of the line.
        var marks: Range<Int>
        /// The marks and the blank after them: what is taken out.
        var removed: Range<Int>
    }

    static func analyze(_ text: String, with analyze: (String) -> [LyricToken]) -> [LyricToken] {
        let chars = Array(text)
        var sites: [Site] = []
        var i = 1
        while i < chars.count {
            guard marks.contains(chars[i]), isHiragana(chars[i - 1]) else { i += 1; continue }
            var j = i
            while j < chars.count, marks.contains(chars[j]) { j += 1 }
            var k = j
            while k < chars.count, chars[k].unicodeScalars.allSatisfy(\.properties.isWhitespace) { k += 1 }
            if k < chars.count, isHiragana(chars[k]) { sites.append(Site(marks: i..<j, removed: i..<k)) }
            i = max(k, i + 1)
        }
        let original = analyze(text)
        guard !sites.isEmpty else { return original }

        // The line without the marks, and where each of its characters
        // sits in the line as written.
        var origin: [Int] = []
        var next = 0
        for site in sites {
            origin.append(contentsOf: next..<site.removed.lowerBound)
            next = site.removed.upperBound
        }
        origin.append(contentsOf: next..<chars.count)
        let plain = analyze(String(origin.map { chars[$0] }))

        // Each word of the plain line, back in the line as written. A
        // mark right after a word draws out that word's last sound.
        var mapped: [(token: LyricToken, inside: [Site], after: Site?)] = []
        for token in plain {
            guard !token.range.isEmpty, token.range.upperBound <= origin.count else { return original }
            let range = origin[token.range.lowerBound]..<(origin[token.range.upperBound - 1] + 1)
            var moved = token
            moved.range = range
            mapped.append(
                (
                    moved, sites.filter { range.contains($0.marks.lowerBound) },
                    sites.first { $0.marks.lowerBound == range.upperBound }
                ))
        }

        // A stretch to take from the plain line: around a word that
        // runs over a mark, widened until both analyses cut at its ends.
        var windows: [Range<Int>] = []
        for entry in mapped where !entry.inside.isEmpty {
            // A word the dictionary knows with its mark (らーめん) stays.
            let known = entry.inside.contains { site in
                original.contains { $0.range.contains(site.marks.lowerBound) && $0.range.upperBound > site.removed.upperBound }
            }
            if known { continue }
            var window = entry.token.range
            while true {
                var wider = window
                for range in original.map(\.range) + mapped.map(\.token.range) where range.overlaps(wider) {
                    wider = min(wider.lowerBound, range.lowerBound)..<max(wider.upperBound, range.upperBound)
                }
                if wider == window { break }
                window = wider
            }
            if let last = windows.last, last.overlaps(window) {
                windows[windows.count - 1] = min(last.lowerBound, window.lowerBound)..<max(last.upperBound, window.upperBound)
            } else {
                windows.append(window)
            }
        }

        var out = original
        for window in windows.reversed() {
            var replacement: [LyricToken] = []
            var readable = true
            for entry in mapped where entry.token.range.overlaps(window) {
                var token = entry.token
                guard let reading = reading(of: token, plainSurface: Array(token.surface), inside: entry.inside, chars: chars)
                else {
                    readable = false
                    break
                }
                token.reading = reading
                if let after = entry.after, window.contains(after.marks.lowerBound) {
                    token.range = token.range.lowerBound..<after.marks.upperBound
                    token.reading += String(repeating: "ー", count: after.marks.count)
                }
                token.surface = String(chars[token.range])
                replacement.append(token)
            }
            guard readable, let first = out.firstIndex(where: { $0.range.overlaps(window) }),
                let last = out.lastIndex(where: { $0.range.overlaps(window) })
            else { continue }
            out.replaceSubrange(first...last, with: replacement)
        }
        return out
    }

    /// The word's reading with a long mark for each mark inside it, or
    /// nil when the place in the reading cannot be told.
    private static func reading(
        of token: LyricToken, plainSurface: [Character], inside: [Site], chars: [Character]
    ) -> String? {
        guard !inside.isEmpty else { return token.reading }
        let reading = Array(Kana.katakana(token.reading))
        var out = Array(token.reading)
        guard out.count == reading.count else { return nil }
        // From the last mark to the first, so earlier places stay put.
        for site in inside.reversed() {
            // The word's characters after the mark, as written.
            let rest = (site.removed.upperBound..<token.range.upperBound).filter { index in
                !inside.contains { $0.removed.contains(index) }
            }
            let tail = Array(Kana.katakana(String(rest.map { chars[$0] })))
            let head = plainSurface.count - tail.count
            let place: Int
            if reading.count >= tail.count, Array(reading.suffix(tail.count)) == tail {
                place = reading.count - tail.count
            } else if head >= 0, Array(reading.prefix(head)) == Array(Kana.katakana(String(plainSurface.prefix(head)))) {
                place = head
            } else {
                return nil
            }
            out.insert(contentsOf: Array(repeating: "ー", count: site.marks.count), at: place)
        }
        return String(out)
    }
}
