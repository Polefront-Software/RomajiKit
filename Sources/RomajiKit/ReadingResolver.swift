import Foundation

/// Picks the reading for one token: the highest-priority source wins,
/// and the source is kept. The reference's `resolve`.
///
/// Proposals are per song and per position, never global: the same
/// kanji is sung differently from song to song.
public enum ReadingResolver {
    public static func resolve(token: LyricToken, proposals: [ReadingProposal] = []) -> ResolvedToken {
        var best = ReadingProposal(reading: token.reading, source: .dictionary, needsReview: token.needsReview)
        for proposal in proposals where proposal.source.priority > best.source.priority {
            best = proposal
        }
        let needsReview: Bool
        switch best.source {
        case .ruby, .user:
            // Written in the lyrics or set by hand: settled, unless the
            // lyrics changed under the fix.
            needsReview = best.needsReview
        case .audio:
            // What was heard is a suggestion, never applied silently.
            needsReview = true
        case .classifier:
            // The pick says for itself how sure it is.
            needsReview = best.needsReview
        case .dictionary, .exception:
            needsReview = token.needsReview || best.needsReview
        }
        var candidates: [String] = []
        for reading in [best.reading, token.reading] + token.candidates + proposals.map(\.reading) {
            let kata = Kana.katakana(reading)
            if !kata.isEmpty, !candidates.contains(kata) { candidates.append(kata) }
        }
        return ResolvedToken(
            token: token, reading: best.reading, source: best.source,
            needsReview: needsReview, candidates: candidates)
    }
}
