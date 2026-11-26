import CryptoKit
import Foundation
import Testing
@testable import RomajiKit

/// The dictionary pack's way onto the device: fetched the first time,
/// looked for again when a look is due, replaced whole or not at all.
/// The "server" is a folder; a file URL is fetched like any other.
@Suite struct PackStoreTests {
    /// A server folder and a device folder, gone when the test is.
    final class Places {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("romaji-pack-\(UUID().uuidString)")
        var server: URL { root.appendingPathComponent("server", isDirectory: true) }
        var device: URL { root.appendingPathComponent("device", isDirectory: true) }

        init() throws { try FileManager.default.createDirectory(at: server, withIntermediateDirectories: true) }
        deinit { try? FileManager.default.removeItem(at: root) }

        /// Puts a pack on the server: files that stand in for a
        /// dictionary, archived as the build script archives the real one.
        func publish(version: String, exceptions: String? = nil, sha256: String? = nil) throws {
            let pack = root.appendingPathComponent("pack-\(version)", isDirectory: true)
            try FileManager.default.createDirectory(at: pack, withIntermediateDirectories: true)
            for name in DictionaryPack.required {
                try Data("\(name) \(version)".utf8).write(to: pack.appendingPathComponent(name))
            }
            if let exceptions { try Data(exceptions.utf8).write(to: pack.appendingPathComponent("exceptions.json")) }
            let archive = "romaji-pack-\(version).aar"
            let aa = Process()
            aa.executableURL = URL(fileURLWithPath: "/usr/bin/aa")
            aa.arguments = ["archive", "-d", pack.path, "-o", server.appendingPathComponent(archive).path, "-a", "lzfse"]
            try aa.run()
            aa.waitUntilExit()
            let data = try Data(contentsOf: server.appendingPathComponent(archive))
            let manifest = PackStore.Manifest(
                version: version, archive: archive, size: data.count,
                sha256: sha256 ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined())
            try JSONEncoder().encode(manifest).write(to: server.appendingPathComponent("manifest.json"))
        }

        func store(interval: TimeInterval = 86_400) -> PackStore {
            PackStore(folder: device, source: server, interval: interval)
        }
    }

    @Test func fetchedOnFirstUse() async throws {
        let places = try Places()
        try places.publish(version: "one")
        let store = places.store()
        #expect(await store.installed == nil)
        #expect(await store.isDue())

        let pack = try #require(try await store.refresh())
        #expect(pack.version == "one")
        #expect(pack.isWhole)
        #expect(await store.installed == pack)
        // Another store, as after the app is started again, finds it.
        #expect(await places.store().installed == pack)
    }

    @Test func looksAgainOnlyWhenDue() async throws {
        let places = try Places()
        try places.publish(version: "one")
        let store = places.store(interval: 100)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = try await store.refresh(now: start)

        try places.publish(version: "two")
        #expect(!(await store.isDue(at: start.addingTimeInterval(99))))
        #expect(try await store.refresh(now: start.addingTimeInterval(99)) == nil)
        #expect(await store.installed?.version == "one")

        let newer = try #require(try await store.refresh(now: start.addingTimeInterval(100)))
        #expect(newer.version == "two")
        // The pack it replaced is cleared away.
        #expect(try FileManager.default.contentsOfDirectory(atPath: places.device.path).sorted() == ["state.json", "two"])
    }

    @Test func sameVersionIsNotFetchedAgain() async throws {
        let places = try Places()
        try places.publish(version: "one")
        let store = places.store(interval: 100)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = try await store.refresh(now: start)
        // Were the archive asked for, this would throw: it is gone.
        try FileManager.default.removeItem(at: places.server.appendingPathComponent("romaji-pack-one.aar"))
        #expect(try await store.refresh(now: start.addingTimeInterval(100)) == nil)
        #expect(!(await store.isDue(at: start.addingTimeInterval(150))))
    }

    @Test func aDamagedArchiveIsNotPutInPlace() async throws {
        let places = try Places()
        try places.publish(version: "one")
        let store = places.store(interval: 100)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = try await store.refresh(now: start)

        try places.publish(version: "two", sha256: String(repeating: "0", count: 64))
        await #expect(throws: PackStore.Failure.wrongHash) {
            try await store.refresh(now: start.addingTimeInterval(100))
        }
        #expect(await store.installed?.version == "one")
        // It waits before asking again, and then does.
        #expect(!(await store.isDue(at: start.addingTimeInterval(101))))
        #expect(await store.isDue(at: start.addingTimeInterval(100 + 3_600)))
    }

    @Test func aVersionThatIsNoFolderNameIsRefused() async throws {
        let places = try Places()
        try places.publish(version: "one")
        let store = places.store(interval: 100)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = try await store.refresh(now: start)

        let manifestURL = places.server.appendingPathComponent("manifest.json")
        var manifest = try JSONDecoder().decode(PackStore.Manifest.self, from: Data(contentsOf: manifestURL))
        // Each a day apart, past the wait after a look that failed.
        for (day, version) in ["../outside", "", ".hidden", "a/b", "two words", "ä"].enumerated() {
            manifest.version = version
            try JSONEncoder().encode(manifest).write(to: manifestURL)
            await #expect(throws: PackStore.Failure.badVersion) {
                try await store.refresh(now: start.addingTimeInterval(Double(day + 1) * 86_400))
            }
            #expect(await store.installed?.version == "one")
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: places.device.path).sorted() == ["one", "state.json"])
        #expect(PackStore.isFolderName("2026.11-a1"))
    }

    @Test func aServerAwayLeavesThePackInUse() async throws {
        let places = try Places()
        try places.publish(version: "one")
        let store = places.store(interval: 100)
        let start = Date(timeIntervalSince1970: 1_000_000)
        _ = try await store.refresh(now: start)
        try FileManager.default.removeItem(at: places.server)
        await #expect(throws: (any Error).self) { try await store.refresh(now: start.addingTimeInterval(100)) }
        #expect(await store.installed?.version == "one")
    }

    @Test func noSourceKeepsWhatIsHere() async throws {
        let places = try Places()
        let store = PackStore(folder: places.device, source: nil)
        #expect(!(await store.isDue()))
        #expect(try await store.refresh() == nil)
    }

    @Test func thePacksOwnListsAreRead() async throws {
        let places = try Places()
        try places.publish(
            version: "one",
            exceptions: #"{"version": 1, "entries": [{"surface": "試験語", "reading": "テスト"}]}"#)
        let pack = try #require(try await places.store().refresh())
        #expect(pack.exceptions.entries.map(\.surface) == ["試験語"])
        // No hints in this pack: the ones built in stand.
        #expect(pack.gikun.words == GikunHints.bundled.words)
    }
}
