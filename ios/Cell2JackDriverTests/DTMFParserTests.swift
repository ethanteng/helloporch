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
        print("DTMF parser: observed capture, every split, bytewise framing, repeats, duplicate diagnostics, config rejection and overflow recovery passed")
    }
}
