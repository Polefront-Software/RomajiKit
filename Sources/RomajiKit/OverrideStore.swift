import CryptoKit
import Foundation

/// Which song a set of readings belongs to: the MusicBrainz recording
/// where the file has one, else the server's own id for the song.
public enum SongIdentity: Sendable, Hashable, Codable {
    case musicBrainz(String)
    case navidrome(String)

    public init(musicBrainzRecordingID: String?, navidromeID: String) {
        if let id = musicBrainzRecordingID?.trimmingCharacters(in: .whitespaces), !id.isEmpty {
            self = .musicBrainz(id.lowercased())
        } else {
            self = .navidrome(navidromeID)
        }
    }

    public var key: String {
        switch self {
        case .musicBrainz(let id): "mbid:\(id)"
        case .navidrome(let id): "nd:\(id)"
        }
    }
}

/// A fingerprint of a song's lyrics, to notice when they change.
public enum LyricsHash {
    public static func make(_ lines: [String]) -> String {
        let text = lines.map(\.precomposedStringWithCanonicalMapping).joined(separator: "\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// One reading fixed for one word of one song.
public struct ReadingOverride: Sendable, Hashable, Codable, Identifiable {
    /// The line, counted from zero.
    public var line: Int
    /// The word's characters in the displayed line.
    public var range: Range<Int>
    /// The word as it was written when the reading was set.
    public var surface: String
    /// The reading, in kana.
    public var reading: String
    public var source: ReadingSource
    /// The lyrics the reading was set against.
    public var lyricsHash: String
    public var modified: Date

    public var id: String { "\(line):\(range.lowerBound)-\(range.upperBound)" }

    public init(
        line: Int, range: Range<Int>, surface: String, reading: String,
        source: ReadingSource = .user, lyricsHash: String, modified: Date = .now
    ) {
        self.line = line
        self.range = range
        self.surface = surface
        self.reading = reading
        self.source = source
        self.lyricsHash = lyricsHash
        self.modified = modified
    }
}

/// A song's overrides as they stand against the lyrics now.
public struct SongOverrides: Sendable, Hashable {
    public var overrides: [ReadingOverride]
    /// The hash of the lyrics being shown.
    public var lyricsHash: String
    /// Counts every change to this song's overrides; part of the cache key.
    public var version: Int

    public static func none(lyricsHash: String = "") -> SongOverrides {
        SongOverrides(overrides: [], lyricsHash: lyricsHash, version: 0)
    }

    /// Set against other lyrics than the ones shown: kept, and to be looked at again.
    public func isStale(_ o: ReadingOverride) -> Bool { o.lyricsHash != lyricsHash }

    public var stale: [ReadingOverride] { overrides.filter(isStale) }

    public func forLine(_ line: Int) -> [ReadingOverride] { overrides.filter { $0.line == line } }
}

/// A song's fixes as they travel between a listener's devices: the
/// readings set, and the places a reading was taken back from, so that
/// a fix removed on one device does not come back from another.
public struct SongFixes: Sendable, Equatable, Codable {
    public var overrides: [ReadingOverride]
    /// When a place's reading was taken back, by the override's id and source.
    public var removed: [String: Date]

    public init(overrides: [ReadingOverride] = [], removed: [String: Date] = [:]) {
        self.overrides = overrides
        self.removed = removed
    }

    public var isEmpty: Bool { overrides.isEmpty && removed.isEmpty }

    /// Both devices' fixes as one: for each place, whatever was done
    /// last, be it a reading set or one taken back.
    public func merged(with other: SongFixes) -> SongFixes {
        var newest: [String: ReadingOverride] = [:]
        for override in overrides + other.overrides {
            if let known = newest[override.place], known.modified >= override.modified { continue }
            newest[override.place] = override
        }
        let gone = removed.merging(other.removed) { max($0, $1) }
        var result = SongFixes()
        for (place, override) in newest where gone[place].map({ override.modified > $0 }) ?? true {
            result.overrides.append(override)
        }
        result.removed = gone.filter { place, when in newest[place].map { $0.modified <= when } ?? true }
        result.overrides.sort { ($0.line, $0.range.lowerBound, $0.source.rawValue) < ($1.line, $1.range.lowerBound, $1.source.rawValue) }
        return result
    }
}

extension ReadingOverride {
    /// Where the override sits and whose it is: one reading per place and source.
    var place: String { "\(id)|\(source.rawValue)" }
}

/// Per-song reading fixes, kept in one file on the device. Never written
/// to the song's tags, and never applied to another song.
///
/// A store can be kept the same on a listener's other devices: it says
/// which song changed (`onChange`), gives that song's fixes (`fixes`),
/// and takes another device's (`merge`).
public actor OverrideStore {
    private struct SongRecord: Codable {
        var version: Int
        var overrides: [ReadingOverride]
        var removed: [String: Date]?

        var fixes: SongFixes { SongFixes(overrides: overrides, removed: removed ?? [:]) }
    }

    private struct File: Codable {
        var schema: Int
        var songs: [String: SongRecord]
    }

    private let fileURL: URL?
    private var songs: [String: SongRecord] = [:]
    private var loaded = false

    private let onChange: (@Sendable (_ song: String) -> Void)?

    /// - Parameters:
    ///   - fileURL: nil keeps everything in memory (tests, previews).
    ///   - onChange: called with a song's key when its fixes were changed
    ///     here; not when they came in through `merge`.
    public init(fileURL: URL?, onChange: (@Sendable (_ song: String) -> Void)? = nil) {
        self.fileURL = fileURL
        self.onChange = onChange
    }

    /// The keys of the songs with fixes, or with fixes taken back.
    public var songKeys: [String] {
        load()
        return songs.keys.sorted()
    }

    /// A song's fixes, to hand to another device.
    public func fixes(forKey song: String) -> SongFixes {
        load()
        return songs[song]?.fixes ?? SongFixes()
    }

    /// Takes in another device's fixes for a song. Returns what the song
    /// has afterwards when that is more than the other device had, so
    /// the caller can send it back; nil when the two now agree.
    @discardableResult
    public func merge(_ other: SongFixes, forKey song: String) -> SongFixes? {
        load()
        let here = songs[song]
        let merged = (here?.fixes ?? SongFixes()).merged(with: other)
        if merged != here?.fixes {
            songs[song] = SongRecord(
                version: (here?.version ?? 0) + 1, overrides: merged.overrides,
                removed: merged.removed.isEmpty ? nil : merged.removed)
            save()
        }
        return merged == other ? nil : merged
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let fileURL, let data = try? Data(contentsOf: fileURL),
            let file = try? JSONDecoder.overrides.decode(File.self, from: data)
        else { return }
        songs = file.songs
    }

    private func save() {
        guard let fileURL else { return }
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder.overrides.encode(File(schema: 1, songs: songs))
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // The fix stays for this run; the next save tries again.
        }
    }

    public func overrides(for song: SongIdentity, lyricsHash: String) -> SongOverrides {
        load()
        let record = songs[song.key]
        return SongOverrides(overrides: record?.overrides ?? [], lyricsHash: lyricsHash, version: record?.version ?? 0)
    }

    /// Sets a reading, replacing any other for the same place and source.
    public func set(_ override: ReadingOverride, for song: SongIdentity) {
        load()
        var record = songs[song.key] ?? SongRecord(version: 0, overrides: [])
        let replaced = record.overrides.filter {
            $0.line == override.line && $0.range.overlaps(override.range) && $0.source == override.source
        }
        record.overrides.removeAll(where: replaced.contains)
        record.overrides.append(override)
        record.overrides.sort { ($0.line, $0.range.lowerBound) < ($1.line, $1.range.lowerBound) }
        var removed = record.removed ?? [:]
        for old in replaced { removed[old.place] = override.modified }
        removed[override.place] = nil
        record.removed = removed.isEmpty ? nil : removed
        record.version += 1
        songs[song.key] = record
        save()
        onChange?(song.key)
    }

    /// Takes a reading back, so the word falls to the next source.
    public func remove(line: Int, range: Range<Int>, source: ReadingSource = .user, for song: SongIdentity) {
        load()
        guard var record = songs[song.key] else { return }
        guard let gone = record.overrides.first(where: { $0.line == line && $0.range == range && $0.source == source })
        else { return }
        record.overrides.removeAll { $0 == gone }
        record.removed = (record.removed ?? [:]).merging([gone.place: .now]) { _, new in new }
        record.version += 1
        songs[song.key] = record
        save()
        onChange?(song.key)
    }

    /// After the user has looked at a stale reading and kept it.
    public func confirm(_ override: ReadingOverride, lyricsHash: String, for song: SongIdentity) {
        var kept = override
        kept.lyricsHash = lyricsHash
        kept.modified = .now
        set(kept, for: song)
    }
}

extension JSONEncoder {
    fileprivate static var overrides: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }
}

extension JSONDecoder {
    fileprivate static var overrides: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
