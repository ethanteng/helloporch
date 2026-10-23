import Foundation

@main struct DTMFParserTests {
    static func main() {
        let observed = " DTMF 1 :0 20: 2\r\n DTMF 2 :1 20: 2\r\n DTMF 3 :2 20: 2\r\n DTMF 0 :3 20: 2\r\n DTMF * :4 20: 2\r\n DTMF # :0 20: 2\r\n"
        for split in 0...observed.utf8.count {
            var parser = Cell2JackDTMFParser()
            let bytes = Data(observed.utf8)
            let result = parser.append(bytes.prefix(split)) + parser.append(bytes.dropFirst(split))
            precondition(result.map(\.digit).joined() == "1230*#")
            precondition(result.allSatisfy { $0.kind == .digit })
        }
        var fragmented = Cell2JackDTMFParser()
        var digits: [Cell2JackDigitEvent] = []
        for byte in observed.utf8 { digits += fragmented.append(Data([byte])) }
        precondition(digits.map(\.digit).joined() == "1230*#")
        var parser = Cell2JackDTMFParser()
        let repeatEvents = parser.append(Data("DTMF 5 :0\nDTMF 5 :1\nDouble DTMF 5\rRX Double DTMF 5\n".utf8))
        precondition(repeatEvents.map(\.digit).joined() == "5555")
        precondition(repeatEvents.map(\.kind) == [.digit, .digit, .doubleReport, .doubleReport])
        let config = "DTMF=1, DTMFO=2\nUnknown DTMF key 1\nDTMFIS=0\nCJ Version = a06\nDTMF 12\nDTMF X\nnot DTMF 1\n"
        precondition(parser.append(Data(config.utf8)).isEmpty)
        let keys = "0123456789*#ABCD"
        precondition(parser.append(Data(keys.map { "DTMF \($0)\r" }.joined().utf8)).map(\.digit).joined() == keys)
        precondition(parser.append(Data("DTMF 9".utf8)).isEmpty)
        parser.resetPartialLine()
        precondition(parser.append(Data(" :0\n".utf8)).isEmpty)
        var oversized = Data(repeating: 32, count: 4097)
        oversized.append(Data("DTMF 8\nDTMF 7\r\n".utf8))
        precondition(parser.append(oversized).map(\.digit) == ["7"])
        precondition(parser.append(Data([0xff] + Array("DTMF 1\n".utf8))).isEmpty)
        precondition(parser.append(Data("DTMF 4\r".utf8)).map(\.digit) == ["4"])
        precondition(parser.append(Data("\n".utf8)).isEmpty)
        let joinedLine = " Cal DTMF 1 :0 20: 2\r\n"
        for split in 0...joinedLine.utf8.count {
            var recovery = Cell2JackDTMFParser()
            let bytes = Data(joinedLine.utf8)
            let recovered = recovery.append(bytes.prefix(split)) + recovery.append(bytes.dropFirst(split))
            precondition(recovered.map(\.digit) == ["1"])
            precondition(recovered[0].embeddedInLine)
        }
        let diagnostic = parser.append(Data(" Cal RX Double DTMF 1 :0 20: 2\n".utf8))
        precondition(diagnostic.count == 1 && diagnostic[0].kind == .doubleReport)
        precondition(parser.append(Data("status mentions DTMF 1\nUnknown DTMF key 1\nstatus DTMF 12 :0 20: 2\n".utf8)).isEmpty)
        // Captured from the bedside's picture phone: the first pickup after reconnecting
        // Cell2Jack broke the line once, which it counted as a pulse-dialed 1. The next
        // pickup's 0 is a real key press.
        let pickups = "L1L2 OFF_HOOK \r\n Set OFF-hook 230\r\n Play tone\r\nH1H2L1L2 FLASH \r\n Set OFF-hook 230\r\n.. Get PULSE 1 1\r\n Stop Playing Dialtone\r\n DTMF 1 :0 20: 2\r\nH1H2.Loop 1: Null Addr\r\n ON_HOOK \r\nL1L2 OFF_HOOK \r\n Play tone\r\n Stop Playing Audio\r\n DTMF 0 :0 20: 2\r\nH1H2 ON_HOOK \r\n"
        for split in 0...pickups.utf8.count {
            var pulses = Cell2JackDTMFParser()
            let bytes = Data(pickups.utf8)
            let events = pulses.append(bytes.prefix(split)) + pulses.append(bytes.dropFirst(split))
            precondition(events.map(\.kind) == [.pulse, .hangUp, .digit, .hangUp])
            precondition(events.filter { $0.kind != .hangUp }.map(\.digit) == ["1", "0"])
        }
        var stale = Cell2JackDTMFParser()
        precondition(stale.append(Data(".. Get PULSE 1 1\r\n ON_HOOK \r\nL1L2 OFF_HOOK \r\n DTMF 3 :0 20: 2\r\n".utf8)).map(\.kind) == [.digit])
        // Captured when Cell2Jack was plugged back in: it reports ON_HOOK as it starts, with no
        // pickup before it. Only putting the receiver back after a pickup is a hang-up.
        var hooks = Cell2JackDTMFParser()
        precondition(hooks.append(Data(" ON_HOOK \r\n Set ON-hook 121\r\n Set Ring = 0\r\n Set ON-hook 121\r\n--Cell2Jack CopyRight00\r\n".utf8)).isEmpty)
        let lifted = hooks.append(Data("L1L2 OFF_HOOK \r\nH1H2L1L2 FLASH \r\n Set OFF-hook 230\r\nH1H2 ON_HOOK \r\n Set ON-hook 121\r\n ON_HOOK \r\n".utf8))
        precondition(lifted.map(\.kind) == [.hangUp] && lifted[0].line == "H1H2 ON_HOOK " && lifted[0].digit.isEmpty)
        precondition(hooks.append(Data("L1L2 OFF_HOOK \r\nNON_HOOKED\r\n DTMF 0 :0 20: 2 H1H2 ON_HOOK \r\n".utf8)).map(\.kind) == [.digit, .hangUp])
        // Logs that start with the receiver already up: a key press shows it was off the cradle.
        var startedLifted = Cell2JackDTMFParser()
        precondition(startedLifted.append(Data(" DTMF 5 :0 20: 2\r\nH1H2 ON_HOOK \r\n ON_HOOK \r\n".utf8)).map(\.kind) == [.digit, .hangUp])
        if CommandLine.arguments.count > 1 {
            var capture = Cell2JackDTMFParser()
            let bytes = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let actual = capture.append(bytes).filter { $0.kind == .digit }
            precondition(actual.map(\.digit).joined() == "1234567890*#")
            precondition(actual.filter(\.embeddedInLine).map(\.digit) == ["1"])
            print("Physical full-keypad capture: all 12 events recovered; joined first-digit line marked")
        }
        print("DTMF parser: observed capture, every split, bytewise framing, repeats, duplicate diagnostics, config rejection, overflow recovery, pickup pulses and hang-ups passed")
    }
}
