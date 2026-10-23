import Foundation

/// Sits between the pty and SwiftTerm's parser and defuses two requests a
/// program in the pane — including one on a remote host behind `ssh` — can
/// make to read what isn't its own. SwiftTerm honours both and has no
/// switch for either:
/// - **DECRQCRA** (`CSI … y`): answers with a checksum of a rectangle of
///   the screen. Asked one cell at a time, the checksum *is* the character,
///   so the program can read everything on screen, including what other
///   programs printed before it.
/// - **Kitty graphics from a file or shared memory** (APC `G` with `t=f`,
///   `t=t` or `t=s`): makes the terminal itself open a local path the
///   program names — it learns from the answer whether the file exists,
///   can make the app load up to 400 MB, trigger a privacy prompt for
///   ~/Documents in this app's name, or unlink a shared-memory object.
///
/// To see each sequence exactly where SwiftTerm acts on it, this runs a
/// shadow copy of SwiftTerm's own parser state machine
/// (`EscapeSequenceParser` in SwiftTerm 1.20.0): the same transition table
/// and the same shortcuts — which make the state depend on where one read
/// ends and the next begins, so every chunk returned by `filter` must be
/// fed to SwiftTerm as one piece, as is. Nothing is dropped; only the byte
/// that would set the request off is changed: a `y` that would dispatch a
/// CSI becomes SUB, which aborts it, and the terminator of a kitty APC that
/// reads a local source is preceded by (or, for BEL and ST, replaced with)
/// CAN, which ends it without dispatching it.
///
/// After updating SwiftTerm, re-check this against its
/// `buildVt500TransitionTable` and `parse(data:)`.
struct HostOutputFilter {
    private static let bel: UInt8 = 0x07
    private static let can: UInt8 = 0x18
    private static let sub: UInt8 = 0x1a
    private static let esc: UInt8 = 0x1b

    private var state: State = .ground
    private var apc = PendingAPC()

    /// How many requests of each kind were defused so far.
    private(set) var defusedScreenReads = 0
    private(set) var defusedLocalSourceReads = 0

    /// `data` as it may be fed to SwiftTerm.
    mutating func filter(_ data: ArraySlice<UInt8>) -> [UInt8] {
        var out: [UInt8] = []
        out.reserveCapacity(data.count + 2)
        var i = data.startIndex
        let end = data.endIndex
        while i < end {
            let code = data[i]

            // SwiftTerm prints such a run without consulting its table.
            if state == .ground && code > 0x1f {
                let start = i
                repeat { i += 1 } while i < end && data[i] > 0x1f
                out.append(contentsOf: data[start..<i])
                continue
            }

            let transition = Self.table[(Int(state.rawValue) << 8) | Int(code < 0xa0 ? code : 0xa0)]
            var next = State(rawValue: transition & 15)!
            switch Action(rawValue: transition >> 4)! {
            case .error:
                if code > 0x9f, state == .csiIgnore || state == .dcsIgnore || state == .dcsPassthrough {
                    next = state
                }

            case .csiDispatch where code == UInt8(ascii: "y"):
                // SwiftTerm answers every `CSI … y` as DECRQCRA.
                out.append(Self.sub)
                defusedScreenReads += 1
                state = .ground
                i += 1
                continue

            case .oscStart, .clear:
                apc = PendingAPC()

            case .oscPut:
                // SwiftTerm takes everything up to BEL, CAN or ESC as string
                // content, again without its table.
                var j = i
                while j < end, data[j] != Self.bel, data[j] != Self.can, data[j] != Self.esc {
                    if state == .apcString && data[j] >= 0x20 { apc.append(data[j]) }
                    j += 1
                }
                out.append(contentsOf: data[i..<j])
                i = j
                continue

            case .oscEnd:
                if state == .apcString && code != Self.can && code != Self.sub && apc.readsLocalSource {
                    out.append(Self.can)
                    defusedLocalSourceReads += 1
                    if code == Self.esc {
                        out.append(code)
                        state = .escape
                    } else {
                        state = .ground
                    }
                    apc = PendingAPC()
                    i += 1
                    continue
                }
                apc = PendingAPC()
                if code == Self.esc { next = .escape }

            case .dcsUnhook:
                if code == Self.esc { next = .escape }

            default:
                break
            }
            out.append(code)
            state = next
            i += 1
        }
        return out
    }

    // MARK: - Kitty graphics

    /// What SwiftTerm has collected of the APC string being received —
    /// enough of it to tell whether, once terminated, it would make the
    /// terminal read a file or shared memory.
    private struct PendingAPC {
        /// Kitty never needs this much before the `;` that ends the keys;
        /// a longer control part is treated as reading a local source.
        static let maxControlLength = 4096

        private var count = 0
        private var command: UInt8 = 0
        private var control: [UInt8] = []
        private var controlComplete = false
        private var controlTooLong = false

        mutating func append(_ byte: UInt8) {
            count += 1
            if count == 1 {
                command = byte
            } else if controlComplete {
                return
            } else if byte == UInt8(ascii: ";") {
                controlComplete = true
            } else if control.count < Self.maxControlLength {
                control.append(byte)
            } else {
                controlTooLong = true
            }
        }

        /// A kitty graphics command whose `t` key asks for anything but
        /// direct (inline) data: `f` file, `t` temporary file, `s` shared
        /// memory. Any such `t`, even one a later `t=d` would override.
        var readsLocalSource: Bool {
            guard count > 0, command == UInt8(ascii: "G") else { return false }
            if controlTooLong { return true }
            return control.split(separator: UInt8(ascii: ","), omittingEmptySubsequences: false).contains { pair in
                guard let eq = pair.firstIndex(of: UInt8(ascii: "=")) else { return false }
                let key = pair[pair.startIndex..<eq]
                let value = pair[(eq + 1)...]
                return key.elementsEqual([UInt8(ascii: "t")]) && value.first.map { $0 != UInt8(ascii: "d") } == true
            }
        }
    }

    // MARK: - SwiftTerm's parser, states and transitions only

    private enum State: UInt8, CaseIterable {
        case ground = 0
        case escape
        case escapeIntermediate
        case csiEntry
        case csiParam
        case csiIntermediate
        case csiIgnore
        case sosPmApcString
        case oscString
        case apcString
        case dcsEntry
        case dcsParam
        case dcsIgnore
        case dcsIntermediate
        case dcsPassthrough
    }

    private enum Action: UInt8 {
        case ignore = 0
        case error
        case print
        case execute
        case oscStart
        case oscPut
        case oscEnd
        case csiDispatch
        case param
        case collect
        case escDispatch
        case clear
        case dcsHook
        case dcsPut
        case dcsUnhook
    }

    /// Entry `(state << 8) | min(code, 0xa0)` is `(action << 4) | next`;
    /// built by the same steps, in the same order (later entries override
    /// earlier ones), as SwiftTerm's `buildVt500TransitionTable`.
    private static let table: [UInt8] = {
        var table = [UInt8](repeating: 0, count: 4095)
        func add(_ codes: [UInt8], _ state: State, _ action: Action, _ next: State) {
            for code in codes {
                table[(Int(state.rawValue) << 8) | Int(code)] = (action.rawValue << 4) | next.rawValue
            }
        }
        func r(_ low: UInt8, _ high: UInt8) -> [UInt8] { Array(low..<high) }

        for state in State.allCases {
            add(Array(0...0xa0), state, .error, .ground)
        }
        let printables = r(0x20, 0x7f)
        let executables = r(0x00, 0x19) + r(0x1c, 0x20)
        add(printables, .ground, .print, .ground)

        for state in State.allCases {
            add([0x18, 0x1a, 0x99, 0x9a], state, .execute, .ground)
            add(r(0x80, 0x90), state, .execute, .ground)
            add(r(0x90, 0x98), state, .execute, .ground)
            add([0x9c], state, .ignore, .ground)
            add([0x1b], state, .clear, .escape)
            add([0x9d], state, .oscStart, .oscString)
            add([0x98, 0x9e], state, .ignore, .sosPmApcString)
            add([0x9f], state, .oscStart, .apcString)
            add([0x9b], state, .clear, .csiEntry)
            add([0x90], state, .clear, .dcsEntry)
        }
        add(executables, .ground, .execute, .ground)
        add(executables, .escape, .execute, .escape)
        add([0x7f], .escape, .ignore, .escape)
        add(executables, .oscString, .ignore, .oscString)
        add(executables, .apcString, .ignore, .apcString)
        add(executables, .csiEntry, .execute, .csiEntry)
        add([0x7f], .csiEntry, .ignore, .csiEntry)
        add(executables, .csiParam, .execute, .csiParam)
        add([0x7f], .csiParam, .ignore, .csiParam)
        add(executables, .csiIgnore, .execute, .csiIgnore)
        add(executables, .csiIntermediate, .execute, .csiIntermediate)
        add([0x7f], .csiIntermediate, .ignore, .csiIntermediate)
        add(executables, .escapeIntermediate, .execute, .escapeIntermediate)
        add([0x7f], .escapeIntermediate, .ignore, .escapeIntermediate)
        // osc
        add([0x5d], .escape, .oscStart, .oscString)
        add(printables, .oscString, .oscPut, .oscString)
        add([0x7f], .oscString, .oscPut, .oscString)
        add([0x9c, 0x1b, 0x18, 0x1a, 0x07], .oscString, .oscEnd, .ground)
        add(r(0x1c, 0x20), .oscString, .ignore, .oscString)
        // apc
        add([0x5f], .escape, .oscStart, .apcString)
        add(printables, .apcString, .oscPut, .apcString)
        add([0x7f], .apcString, .oscPut, .apcString)
        add([0x9c, 0x1b, 0x18, 0x1a, 0x07], .apcString, .oscEnd, .ground)
        add(r(0x1c, 0x20), .apcString, .ignore, .apcString)
        // sos/pm
        add([0x58, 0x5e], .escape, .ignore, .sosPmApcString)
        add(printables, .sosPmApcString, .ignore, .sosPmApcString)
        add(executables, .sosPmApcString, .ignore, .sosPmApcString)
        add([0x9c], .sosPmApcString, .ignore, .ground)
        add([0x7f], .sosPmApcString, .ignore, .sosPmApcString)
        // csi
        add([0x5b], .escape, .clear, .csiEntry)
        add(r(0x40, 0x7f), .csiEntry, .csiDispatch, .ground)
        add(r(0x30, 0x3a), .csiEntry, .param, .csiParam)
        add([0x3b], .csiEntry, .param, .csiParam)
        add([0x3c, 0x3d, 0x3e, 0x3f], .csiEntry, .collect, .csiParam)
        add(r(0x30, 0x3a), .csiParam, .param, .csiParam)
        add([0x3b], .csiParam, .param, .csiParam)
        add(r(0x40, 0x7f), .csiParam, .csiDispatch, .ground)
        add([0x3c, 0x3d, 0x3e, 0x3f], .csiParam, .ignore, .csiIgnore)
        add([0x3a], .csiParam, .param, .csiParam)
        add(r(0x20, 0x40), .csiIgnore, .ignore, .csiIgnore)
        add([0x7f], .csiIgnore, .ignore, .csiIgnore)
        add(r(0x40, 0x7f), .csiIgnore, .ignore, .ground)
        add(r(0x20, 0x30), .csiEntry, .collect, .csiIntermediate)
        add(r(0x20, 0x30), .csiIntermediate, .collect, .csiIntermediate)
        add(r(0x30, 0x40), .csiIntermediate, .ignore, .csiIgnore)
        add(r(0x40, 0x7f), .csiIntermediate, .csiDispatch, .ground)
        add(r(0x20, 0x30), .csiParam, .collect, .csiIntermediate)
        // esc intermediate
        add(r(0x20, 0x30), .escape, .collect, .escapeIntermediate)
        add(r(0x20, 0x30), .escapeIntermediate, .collect, .escapeIntermediate)
        add(r(0x30, 0x7f), .escapeIntermediate, .escDispatch, .ground)
        add(r(0x30, 0x50), .escape, .escDispatch, .ground)
        add(r(0x51, 0x58), .escape, .escDispatch, .ground)
        add([0x59, 0x5a, 0x5c], .escape, .escDispatch, .ground)
        add(r(0x60, 0x7f), .escape, .escDispatch, .ground)
        // dcs
        add([0x50], .escape, .clear, .dcsEntry)
        add(executables, .dcsEntry, .ignore, .dcsEntry)
        add([0x7f], .dcsEntry, .ignore, .dcsEntry)
        add(r(0x1c, 0x20), .dcsEntry, .ignore, .dcsEntry)
        add(r(0x20, 0x30), .dcsEntry, .collect, .dcsIntermediate)
        add([0x3a], .dcsEntry, .ignore, .dcsIgnore)
        add(r(0x30, 0x3a), .dcsEntry, .param, .dcsParam)
        add([0x3b], .dcsEntry, .param, .dcsParam)
        add([0x3c, 0x3d, 0x3e, 0x3f], .dcsEntry, .collect, .dcsParam)
        add(executables, .dcsIgnore, .ignore, .dcsIgnore)
        add(r(0x20, 0x80), .dcsIgnore, .ignore, .dcsIgnore)
        add(r(0x1c, 0x20), .dcsIgnore, .ignore, .dcsIgnore)
        add(executables, .dcsParam, .ignore, .dcsParam)
        add([0x7f], .dcsParam, .ignore, .dcsParam)
        add(r(0x1c, 0x20), .dcsParam, .ignore, .dcsParam)
        add(r(0x30, 0x3a), .dcsParam, .param, .dcsParam)
        add([0x3b], .dcsParam, .param, .dcsParam)
        add([0x3a, 0x3c, 0x3d, 0x3e, 0x3f], .dcsParam, .ignore, .dcsIgnore)
        add(r(0x20, 0x30), .dcsParam, .collect, .dcsIntermediate)
        add(executables, .dcsIntermediate, .ignore, .dcsIntermediate)
        add([0x7f], .dcsIntermediate, .ignore, .dcsIntermediate)
        add(r(0x1c, 0x20), .dcsIntermediate, .ignore, .dcsIntermediate)
        add(r(0x20, 0x30), .dcsIntermediate, .collect, .dcsIntermediate)
        add(r(0x30, 0x40), .dcsIntermediate, .ignore, .dcsIgnore)
        add(r(0x40, 0x7f), .dcsIntermediate, .dcsHook, .dcsPassthrough)
        add(r(0x40, 0x7f), .dcsParam, .dcsHook, .dcsPassthrough)
        add(r(0x40, 0x7f), .dcsEntry, .dcsHook, .dcsPassthrough)
        add(executables, .dcsPassthrough, .dcsPut, .dcsPassthrough)
        add(printables, .dcsPassthrough, .dcsPut, .dcsPassthrough)
        add([0x7f], .dcsPassthrough, .ignore, .dcsPassthrough)
        add([0x1b, 0x9c], .dcsPassthrough, .dcsUnhook, .ground)
        add([0xa0], .oscString, .oscPut, .oscString)
        add([0xa0], .apcString, .oscPut, .apcString)
        return table
    }()
}
