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

/// Per-song reading fixes, kept in one file on the device. Never written
/// to the song's tags, and never applied to another song.
public actor OverrideStore {
    private struct SongRecord: Codable {
        var version: Int
        var overrides: [ReadingOverride]
    }

    private struct File: Codable {
        var schema: Int
        var songs: [String: SongRecord]
    }

    private let fileURL: URL?
    private var songs: [String: SongRecord] = [:]
    private var loaded = false

    /// `fileURL` nil keeps everything in memory (tests, previews).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
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
        record.overrides.removeAll {
            $0.line == override.line && $0.range.overlaps(override.range) && $0.source == override.source
        }
        record.overrides.append(override)
        record.overrides.sort { ($0.line, $0.range.lowerBound) < ($1.line, $1.range.lowerBound) }
        record.version += 1
        songs[song.key] = record
        save()
    }

    /// Takes a reading back, so the word falls to the next source.
    public func remove(line: Int, range: Range<Int>, source: ReadingSource = .user, for song: SongIdentity) {
        load()
        guard var record = songs[song.key] else { return }
        let before = record.overrides.count
        record.overrides.removeAll { $0.line == line && $0.range == range && $0.source == source }
        guard record.overrides.count != before else { return }
        record.version += 1
        songs[song.key] = record
        save()
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
