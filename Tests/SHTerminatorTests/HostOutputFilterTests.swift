import Foundation
import SwiftTerm
import Testing
@testable import SHTerminator

/// A bare SwiftTerm `Terminal` (the same parser the app's view uses) that
/// records what it answers the program — i.e. what a program in the pane,
/// or a remote host behind `ssh`, would get to read.
private final class AnsweringTerminal: TerminalDelegate {
    private(set) var answers: [UInt8] = []
    private(set) lazy var terminal = Terminal(delegate: self)

    func send(source: Terminal, data: ArraySlice<UInt8>) {
        answers.append(contentsOf: data)
    }

    /// As SwiftTerm's macOS view answers.
    func isProcessTrusted(source: Terminal) -> Bool {
        true
    }

    func feed(_ bytes: [UInt8]) {
        terminal.feed(buffer: bytes[...])
    }

    var answerText: String {
        String(decoding: answers, as: UTF8.self)
    }

    /// DECRQCRA answers look like `DCS <id> ! ~ <checksum> ST`.
    var screenChecksums: Int {
        answerText.components(separatedBy: "!~").count - 1
    }

    /// Only loading a file names a "bad path" in its error.
    var fileLoads: Int {
        answerText.components(separatedBy: "bad path").count - 1
            + answerText.components(separatedBy: "bad temp path").count - 1
    }
}

private func bytes(_ text: String) -> [UInt8] {
    Array(text.utf8)
}

private let esc = "\u{1b}"

/// Kitty graphics: transmit from the file at `path` (base64, as kitty wants it).
private func kittyFileRequest(_ path: String, medium: String = "f") -> String {
    "\(esc)_Ga=T,t=\(medium),i=7;\(Data(path.utf8).base64EncodedString())\(esc)\\"
}

private let missingPath = "/nonexistent-\(UUID().uuidString)/id_ed25519"

@Suite struct HostOutputFilterTests {
    @Test func screenChecksumRequestIsAnsweredWithoutTheFilter() {
        // Cell (1,1) holds "s": its checksum is the character code itself.
        let request = bytes("secret\(esc)[1;1;1;1;1;1*y")
        let raw = AnsweringTerminal()
        raw.feed(request)
        #expect(raw.answerText.contains("1!~0073"))

        var filter = HostOutputFilter()
        let filtered = AnsweringTerminal()
        filtered.feed(filter.filter(request[...]))
        #expect(filtered.screenChecksums == 0)
        #expect(filter.defusedScreenReads == 1)
    }

    @Test func eightBitCsiAfterAnOscIsCaughtToo() {
        // In a string state SwiftTerm takes the C1 CSI byte (0x9B) from its
        // table when it starts a read — a request split exactly there.
        let chunks: [[UInt8]] = [bytes("\(esc)]0;title"), [0x9b] + bytes("1;1;1;1;1y")]
        let raw = AnsweringTerminal()
        chunks.forEach(raw.feed)
        #expect(raw.screenChecksums == 1)

        var filter = HostOutputFilter()
        let filtered = AnsweringTerminal()
        for chunk in chunks { filtered.feed(filter.filter(chunk[...])) }
        #expect(filtered.screenChecksums == 0)
    }

    @Test func kittyFileReadIsAnsweredWithoutTheFilter() {
        for medium in ["f", "t"] {
            let request = bytes(kittyFileRequest(missingPath, medium: medium))
            let raw = AnsweringTerminal()
            raw.feed(request)
            #expect(raw.fileLoads == 1)

            var filter = HostOutputFilter()
            let filtered = AnsweringTerminal()
            filtered.feed(filter.filter(request[...]))
            #expect(filtered.fileLoads == 0)
            #expect(filtered.answers.isEmpty)
            #expect(filter.defusedLocalSourceReads == 1)
        }
    }

    @Test func kittyFileReadEndedByBellOrSplitAnywhereIsCaught() {
        let request = bytes("\(esc)_Ga=q,t=f,i=1;\(Data(missingPath.utf8).base64EncodedString())\u{07}after")
        for split in 0...request.count {
            var filter = HostOutputFilter()
            let filtered = AnsweringTerminal()
            filtered.feed(filter.filter(request[..<split]))
            filtered.feed(filter.filter(request[split...]))
            #expect(filtered.fileLoads == 0, "split at \(split)")
        }
    }

    @Test func ordinaryOutputPassesUnchanged() {
        let output = [
            "plain text, Привет, 😀👩‍👩‍👦‍👦, Л",
            "\(esc)[1;31mred\(esc)[0m \(esc)[?2004h\(esc)[2J\(esc)[H\(esc)[38;2;1;2;3m",
            "\(esc)]0;title\u{07}\(esc)]2;other title\(esc)\\",
            "\(esc)]8;;https://example.com\(esc)\\link\(esc)]8;;\(esc)\\",
            "\(esc)P$qm\(esc)\\",
            // Inline kitty image data (t=d, the default) is fine.
            "\(esc)_Ga=T,f=24,s=1,v=1,t=d;AAAA\(esc)\\\(esc)_Ga=T,f=24,s=1,v=1;AAAA\(esc)\\",
            "\r\n\t\u{08}",
        ].joined()
        let data = bytes(output)
        for chunkSize in [1, 2, 3, 7, data.count] {
            var filter = HostOutputFilter()
            var out: [UInt8] = []
            var start = 0
            while start < data.count {
                let end = min(start + chunkSize, data.count)
                out += filter.filter(data[start..<end])
                start = end
            }
            #expect(out == data, "chunk size \(chunkSize)")
        }
    }

    /// Random output — escape sequences, C1 bytes, UTF-8, the two requests
    /// and pieces of them — in random reads: the filter must catch every
    /// screen read SwiftTerm would answer, and nothing else.
    @Test func fuzzAgainstSwiftTermsParser() {
        var rng = SplitMix64(seed: 0x5348_5445_524d)
        let filePiece = "a=q,t=f,i=1;\(Data(missingPath.utf8).base64EncodedString())"
        let tokens: [[UInt8]] = [
            bytes("\(esc)["), [0x9b], bytes("1;1;1;1;1"), bytes(";"), bytes("1"), bytes("*"), bytes("y"),
            bytes("$"), bytes("?"), bytes(":"), bytes("m"),
            bytes("\(esc)[1;1;1;1;1;1*y"), [0x9b] + bytes("2;1;1;2;2*y"),
            bytes("\(esc)]0;"), [0x9d], bytes("\(esc)P"), [0x90], bytes("\(esc)_"), [0x9f], bytes("G"),
            bytes(filePiece), bytes(kittyFileRequest(missingPath)), bytes("\(esc)_G\(filePiece)\u{07}"),
            bytes("\(esc)\\"), bytes("\u{07}"), bytes("\u{18}"), bytes("\u{1a}"), [0x9c], [0x98], [0x85],
            bytes("\(esc)"), bytes("\(esc) "), bytes("text "), bytes("Привет😀"), bytes("\r\n"), [0x7f],
            [0xc2], [0xa0], [0xff],
        ]
        var rawChecksums = 0
        var defused = 0
        var rawLoads = 0
        for _ in 0..<300 {
            var stream: [UInt8] = []
            for _ in 0..<200 { stream += tokens[Int(rng.next() % UInt64(tokens.count))] }

            var filter = HostOutputFilter()
            let raw = AnsweringTerminal()
            let filtered = AnsweringTerminal()
            var start = 0
            while start < stream.count {
                let end = min(start + 1 + Int(rng.next() % 40), stream.count)
                raw.feed(Array(stream[start..<end]))
                filtered.feed(filter.filter(stream[start..<end]))
                start = end
            }
            #expect(filtered.screenChecksums == 0)
            #expect(filtered.fileLoads == 0)
            rawChecksums += raw.screenChecksums
            rawLoads += raw.fileLoads
            defused += filter.defusedScreenReads
        }
        // The fuzz really exercised both, and the shadow parser saw exactly
        // the screen reads SwiftTerm answers (SwiftTerm skips one only past
        // 24 parameters, which these tokens don't reach).
        #expect(rawChecksums > 100)
        #expect(rawLoads > 100)
        #expect(defused == rawChecksums)
    }
}

private struct SplitMix64 {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
}
