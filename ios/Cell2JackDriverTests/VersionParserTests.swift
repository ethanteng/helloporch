import Foundation

@main struct VersionParserTests {
    static func main() {
        func version(_ text: String) -> String? { Cell2JackVersionResult(bytes: Data(text.utf8)).version }
        precondition(version(" >>>>>>>>>>>>>> CJ Version = a06\r\n") == "a06")
        precondition(version("CJ Version = A06\r\n") == "A06")
        precondition(version("DTMF 1 :0 20: 2\r\n") == nil)
        precondition(version("CJ Version = a0") == nil)
        precondition(version("CJ Version = a061\n") == nil)
        precondition(version("") == nil)
        let first = Data(" >>> CJ Ver".utf8), second = Data("sion = a06\r\n".utf8)
        precondition(Cell2JackVersionResult(bytes: first).version == nil)
        precondition(Cell2JackVersionResult(bytes: first + second).version == "a06")
        let binary = Cell2JackVersionResult(bytes: Data([0, 0xff, 0x0a, 0x41]))
        precondition(binary.version == nil)
        precondition(binary.displayText == "\\x00\\xff\nA")
        precondition(binary.hex == "00 ff 0a 41")
        print("Version parser: observed response, fragmentation, malformed data and raw rendering passed")
    }
}
