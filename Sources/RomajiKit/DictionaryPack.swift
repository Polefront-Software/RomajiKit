import AppleArchive
import CryptoKit
import Foundation
import System

/// A dictionary on disk and the lists that go with it: what
/// `scripts/romaji-dictionary.sh` builds and the app fetches.
public struct DictionaryPack: Sendable, Equatable {
    /// MeCab's files, and beside them the exception list and the hints.
    public let folder: URL
    /// A hash of the contents: another version is another dictionary.
    public let version: String

    public init(folder: URL, version: String) {
        self.folder = folder
        self.version = version
    }

    /// The files MeCab will not open a dictionary without.
    static let required = ["sys.dic", "unk.dic", "char.bin", "matrix.bin", "dicrc"]

    var isWhole: Bool {
        Self.required.allSatisfy { FileManager.default.fileExists(atPath: folder.appendingPathComponent($0).path) }
    }

    /// The pack's own lists; the ones built into the package where it
    /// has none, as a folder holding a dictionary alone does not.
    var exceptions: ExceptionList {
        (try? ExceptionList(data: Data(contentsOf: folder.appendingPathComponent("exceptions.json")))) ?? .bundled
    }

    var gikun: GikunHints {
        (try? GikunHints(data: Data(contentsOf: folder.appendingPathComponent("gikun-hints.json")))) ?? .bundled
    }
}

/// Keeps the dictionary pack on the device: fetches it the first time,
/// and looks now and then whether its source has a newer one.
///
/// The source is a folder on a server holding `manifest.json` and the
/// archive it names. The manifest is a few hundred bytes, so looking is
/// cheap; the archive is fetched only when its version is not the one
/// here. A pack is put in place whole or not at all: it is checked
/// against the manifest's hash, unpacked beside the one in use, and
/// only then takes its place.
public actor PackStore {
    /// What the source says it has.
    public struct Manifest: Codable, Sendable, Equatable {
        public var version: String
        /// The archive's name, beside the manifest.
        public var archive: String
        public var size: Int
        public var sha256: String
    }

    public enum Failure: Error, Equatable {
        case noSource
        case notFetched(URL)
        case wrongHash
        case notUnpacked
        /// The manifest's version is not a name a folder may have.
        case badVersion
    }

    /// Whether a version can name the pack's folder: letters, digits,
    /// dots and hyphens, not starting with a dot. Anything else could
    /// reach outside the packs' folder, or hide the pack.
    static func isFolderName(_ version: String) -> Bool {
        guard let first = version.first, first != "." else { return false }
        return version.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "-")
        }
    }

    private struct State: Codable {
        var version: String?
        /// When the source may next be asked.
        var due: Date?
    }

    private let folder: URL
    private let source: URL?
    private let interval: TimeInterval
    private let retry: TimeInterval
    private let session: URLSession
    private var state: State
    private var fetch: Task<DictionaryPack?, any Error>?

    /// - Parameters:
    ///   - folder: where packs are kept; made when first needed.
    ///   - source: the folder on the server; nil keeps what is here.
    ///   - interval: how long a look at the source holds.
    ///   - retry: how soon to look again after a look that failed.
    public init(
        folder: URL, source: URL?, interval: TimeInterval = 86_400, retry: TimeInterval = 3_600,
        session: URLSession = .shared
    ) {
        self.folder = folder
        self.source = source
        self.interval = interval
        self.retry = retry
        self.session = session
        state = (try? JSONDecoder().decode(State.self, from: Data(contentsOf: folder.appendingPathComponent("state.json"))))
            ?? State()
    }

    /// The pack on the device, if one is here and whole.
    public var installed: DictionaryPack? {
        guard let version = state.version, Self.isFolderName(version) else { return nil }
        let pack = DictionaryPack(folder: folder.appendingPathComponent(version, isDirectory: true), version: version)
        return pack.isWhole ? pack : nil
    }

    /// Whether it is time to ask the source: always while no pack is
    /// here, otherwise once the last look has aged.
    public func isDue(at now: Date = .now) -> Bool {
        source != nil && (installed == nil || state.due.map { now >= $0 } ?? true)
    }

    /// Asks the source when a look is due, and fetches its pack when it
    /// is not the one here. Returns the pack newly put in place, or nil
    /// when there was nothing to do. Callers at the same moment share
    /// one fetch.
    public func refresh(now: Date = .now) async throws -> DictionaryPack? {
        if let fetch { return try await fetch.value }
        guard isDue(at: now) else { return nil }
        let task = Task { try await self.fetchIfNewer(now: now) }
        fetch = task
        defer { fetch = nil }
        do {
            return try await task.value
        } catch {
            // With a pack here, the source is left alone for a while
            // after a look that failed; without one, the next song asks.
            state.due = now.addingTimeInterval(retry)
            try? save()
            throw error
        }
    }

    private func fetchIfNewer(now: Date) async throws -> DictionaryPack? {
        guard let source else { throw Failure.noSource }
        let manifest = try JSONDecoder().decode(
            Manifest.self, from: try await data(from: source.appendingPathComponent("manifest.json")))
        defer {
            state.due = now.addingTimeInterval(interval)
            try? save()
        }
        guard Self.isFolderName(manifest.version) else { throw Failure.badVersion }
        if manifest.version == state.version, installed != nil { return nil }

        let (archive, response) = try await session.download(from: source.appendingPathComponent(manifest.archive))
        defer { try? FileManager.default.removeItem(at: archive) }
        guard Self.isOK(response) else { throw Failure.notFetched(source.appendingPathComponent(manifest.archive)) }
        guard try Self.sha256(of: archive) == manifest.sha256.lowercased() else { throw Failure.wrongHash }

        let pack = DictionaryPack(
            folder: folder.appendingPathComponent(manifest.version, isDirectory: true), version: manifest.version)
        let unpacking = folder.appendingPathComponent(manifest.version + ".unpacking", isDirectory: true)
        try? FileManager.default.removeItem(at: unpacking)
        try FileManager.default.createDirectory(at: unpacking, withIntermediateDirectories: true)
        try Self.unpack(archive, into: unpacking)
        try? FileManager.default.removeItem(at: pack.folder)
        try FileManager.default.moveItem(at: unpacking, to: pack.folder)
        guard pack.isWhole else {
            try? FileManager.default.removeItem(at: pack.folder)
            throw Failure.notUnpacked
        }
        state.version = manifest.version
        try save()
        clearOthers(than: manifest.version)
        return pack
    }

    private func data(from url: URL) async throws -> Data {
        // The manifest is asked for afresh: a cached one would hide a new pack.
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard Self.isOK(response) else { throw Failure.notFetched(url) }
        return data
    }

    /// A file URL has no status; a server's must be a 200.
    private static func isOK(_ response: URLResponse) -> Bool {
        (response as? HTTPURLResponse).map { $0.statusCode == 200 } ?? true
    }

    private func save() throws {
        var folder = folder
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // It can be fetched again; no need for it in a backup.
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? folder.setResourceValues(values)
        try JSONEncoder().encode(state).write(to: folder.appendingPathComponent("state.json"), options: .atomic)
    }

    /// Packs no longer in use, and what a fetch that was cut short left.
    /// A dictionary still open stays readable until it is closed.
    private func clearOthers(than version: String) {
        let kept = [version, "state.json"]
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where !kept.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Unpacks an Apple Archive, as `aa archive` writes it.
    private static func unpack(_ archive: URL, into folder: URL) throws {
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .readOnly, options: [], permissions: [.ownerRead]),
            let plain = ArchiveByteStream.decompressionStream(readingFrom: file),
            let entries = ArchiveStream.decodeStream(readingFrom: plain),
            let files = ArchiveStream.extractStream(extractingTo: FilePath(folder.path), flags: [.ignoreOperationNotPermitted])
        else { throw Failure.notUnpacked }
        defer {
            try? files.close()
            try? entries.close()
            try? plain.close()
            try? file.close()
        }
        _ = try ArchiveStream.process(readingFrom: entries, writingTo: files)
    }
}
