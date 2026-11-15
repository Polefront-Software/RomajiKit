import Foundation

/// A reading put forward for a stretch of a line by something that
/// looks at the words around it.
public struct ReadingPick: Sendable, Hashable {
    /// The stretch, counted in the characters of the line as shown. It
    /// starts and ends where words do.
    public var range: Range<Int>
    /// The whole stretch's reading, in kana.
    public var reading: String
    /// The pick is a best guess: the word stays marked for review.
    public var needsReview: Bool
    /// Other readings worth offering for the stretch, in kana.
    public var candidates: [String]

    public init(range: Range<Int>, reading: String, needsReview: Bool = false, candidates: [String] = []) {
        self.range = range
        self.reading = reading
        self.needsReview = needsReview
        self.candidates = candidates
    }
}

/// Picks among the readings a word can have from what stands around
/// it. The engine asks once per line, after the dictionary, the numbers
/// and the exception list have had their say, and takes each pick as a
/// proposal of source `.classifier`: over the dictionary and the
/// exception list, under furigana written in the lyrics and the
/// listener's own fixes.
public protocol ReadingDisambiguator: Sendable {
    /// The picks for one line. `tokens` are the line's words as read so
    /// far, with their places in `line`.
    func picks(for tokens: [LyricToken], in line: String) -> [ReadingPick]
}
