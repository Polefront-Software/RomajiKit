import Foundation
import IPADic
import RomajiKit

// usage: romaji [--preset singalong|learner|official|kunrei] [--tokens] [--system] [--dictionary FOLDER] < lines
// Reads lyric lines from standard input and prints the romaji of each.
// Without --dictionary it reads with the full IPAdic; with it, with a
// pack as scripts/romaji-dictionary.sh builds one.

var preset = RomajiPreset.singalong
var showTokens = false
var useSystem = false
var pack = DictionaryPack(folder: IPADic().url, version: "ipadic")
var arguments = CommandLine.arguments.dropFirst()
while let argument = arguments.popFirst() {
    switch argument {
    case "--preset": preset = arguments.popFirst().flatMap(RomajiPreset.init(rawValue:)) ?? preset
    case "--tokens": showTokens = true
    case "--system": useSystem = true
    case "--dictionary":
        pack = DictionaryPack(folder: URL(fileURLWithPath: arguments.popFirst() ?? "", isDirectory: true), version: "given")
    default:
        FileHandle.standardError.write(Data("usage: romaji [--preset NAME] [--tokens] [--system] [--dictionary FOLDER] < lines\n".utf8))
        exit(2)
    }
}

let engine: RomajiEngine
if useSystem {
    engine = RomajiEngine(analyzer: SystemAnalyzer())
} else if let base = try? RomajiEngine(pack: pack) {
    engine = base
} else {
    FileHandle.standardError.write(Data("The dictionary could not be opened.\n".utf8))
    exit(1)
}

while let line = readLine() {
    let result = engine.romanize(line: line, preset: preset)
    print(result.text)
    if showTokens {
        for token in result.tokens {
            let t = token.resolved.token
            print(
                "    \(t.surface)\t\(token.resolved.reading)\t\(t.pos.rawValue)\(t.attach ? "+" : "")\t\(token.resolved.source.rawValue)\(token.needsReview ? " ?" : "")\t\(token.romaji)"
            )
        }
    }
}
