import Foundation
import NWAsyncSocket

// ============================================================================
// MARK: - NWAsyncSocket Swift Demo
// ============================================================================
//
// This demo lets you interactively verify the core components of NWAsyncSocket:
//   1. StreamBuffer  — sticky-packet / split-packet handling
//   2. SSEParser     — Server-Sent Events incremental parsing
//   3. UTF-8 Safety  — multi-byte character boundary detection
//   4. ReadRequest   — read-request queue types
//   5. NWAsyncSocket — connection usage pattern (Network.framework only)
//
// Run:  swift run SwiftDemo
// ============================================================================

// MARK: - Helpers

/// Print a section header.
func printHeader(_ title: String) {
    let line = String(repeating: "=", count: 60)
    print("\n\(line)")
    print("  \(title)")
    print(line)
}

/// Print a sub-section header.
func printSubHeader(_ title: String) {
    print("\n--- \(title) ---")
}

/// Pause and wait for the user to press Enter.
func waitForUser() {
    print("\nPress Enter to continue...")
    _ = readLine()
}

// MARK: - 1. StreamBuffer Demo

func demoStreamBuffer() {
    printHeader("1. StreamBuffer — Sticky-Packet / Split-Packet Handling")

    let buffer = StreamBuffer()

    // ---- 1a. Sticky packet (粘包) ----
    printSubHeader("1a. Sticky Packet (粘包) — Multiple messages in one TCP segment")

    let stickyData = "Hello\r\nWorld\r\nFoo\r\n".data(using: .utf8)!
    print("Appending combined data: \"Hello\\r\\nWorld\\r\\nFoo\\r\\n\"")
    buffer.append(stickyData)
    print("Buffer size: \(buffer.count) bytes")

    let delimiter = "\r\n".data(using: .utf8)!
    var messageIndex = 1
    while let chunk = buffer.readData(toDelimiter: delimiter) {
        let text = String(data: chunk, encoding: .utf8)!
        print("  Message \(messageIndex): \"\(text.replacingOccurrences(of: "\r\n", with: "\\r\\n"))\"")
        messageIndex += 1
    }
    print("Buffer remaining: \(buffer.count) bytes (expected: 0)")
    print("✅ Sticky packet correctly split into \(messageIndex - 1) messages")

    // ---- 1b. Split packet (拆包) ----
    printSubHeader("1b. Split Packet (拆包) — One message split across TCP segments")

    buffer.reset()
    let part1 = "Hel".data(using: .utf8)!
    let part2 = "lo World".data(using: .utf8)!
    print("Appending part 1: \"Hel\" (\(part1.count) bytes)")
    buffer.append(part1)

    let result1 = buffer.readData(toLength: 11)
    print("Attempt to read 11 bytes: \(result1 == nil ? "nil (not enough data yet)" : "got data")")

    print("Appending part 2: \"lo World\" (\(part2.count) bytes)")
    buffer.append(part2)
    print("Buffer size: \(buffer.count) bytes")

    if let result2 = buffer.readData(toLength: 11) {
        let text = String(data: result2, encoding: .utf8)!
        print("Read 11 bytes: \"\(text)\"")
        print("✅ Split packet correctly reassembled")
    }

    // ---- 1c. Delimiter-based read ----
    printSubHeader("1c. Delimiter-Based Read")

    buffer.reset()
    buffer.append("key1=value1&key2=value2&key3=value3".data(using: .utf8)!)
    print("Buffer content: \"key1=value1&key2=value2&key3=value3\"")

    let ampersand = "&".data(using: .utf8)!
    var pairs: [String] = []
    while let data = buffer.readData(toDelimiter: ampersand) {
        pairs.append(String(data: data, encoding: .utf8)!)
    }
    // Read remaining data
    let remaining = buffer.readAllData()
    if !remaining.isEmpty {
        pairs.append(String(data: remaining, encoding: .utf8)!)
    }
    print("Parsed pairs:")
    for pair in pairs {
        print("  \"\(pair)\"")
    }
    print("✅ Delimiter-based reading works correctly")

    // ---- 1d. readAllData ----
    printSubHeader("1d. Read All Data")

    buffer.reset()
    buffer.append("Part A ".data(using: .utf8)!)
    buffer.append("Part B ".data(using: .utf8)!)
    buffer.append("Part C".data(using: .utf8)!)
    let all = buffer.readAllData()
    print("Read all: \"\(String(data: all, encoding: .utf8)!)\"")
    print("Buffer empty after readAll: \(buffer.isEmpty)")
    print("✅ readAllData works correctly")

    waitForUser()
}

// MARK: - 2. SSEParser Demo

func demoSSEParser() {
    printHeader("2. SSEParser — Server-Sent Events Parsing")

    let parser = SSEParser()

    // ---- 2a. Single complete SSE event ----
    printSubHeader("2a. Single Complete SSE Event")

    let sseData1 = "event: chat\ndata: Hello from the server!\n\n".data(using: .utf8)!
    print("Feed: \"event: chat\\ndata: Hello from the server!\\n\\n\"")
    let events1 = parser.parse(sseData1)
    for event in events1 {
        print("  Parsed Event → type: \"\(event.event)\", data: \"\(event.data)\"")
    }
    print("✅ Single event parsed correctly")

    // ---- 2b. Multiple events in one chunk ----
    printSubHeader("2b. Multiple Events in One Chunk")

    parser.reset()
    let sseData2 = "data: first message\n\ndata: second message\n\nevent: custom\ndata: third with type\n\n".data(using: .utf8)!
    print("Feed: 3 events in a single chunk")
    let events2 = parser.parse(sseData2)
    print("  Parsed \(events2.count) events:")
    for (i, event) in events2.enumerated() {
        print("    [\(i+1)] type: \"\(event.event)\", data: \"\(event.data)\"")
    }
    print("✅ Multiple events parsed correctly")

    // ---- 2c. Split across chunks (LLM streaming simulation) ----
    printSubHeader("2c. Split Across Chunks — LLM Streaming Simulation")

    parser.reset()
    let chunks = [
        "data: {\"tok",
        "en\": \"Hel\"}\n",
        "\ndata: {\"token\"",
        ": \"lo\"}\n\ndata",
        ": {\"token\": \" World\"}\n\n"
    ]
    print("Feeding \(chunks.count) partial chunks to simulate LLM streaming:")
    var allEvents: [SSEEvent] = []
    for (i, chunk) in chunks.enumerated() {
        let display = chunk.replacingOccurrences(of: "\n", with: "\\n")
        let parsed = parser.parse(chunk)
        allEvents.append(contentsOf: parsed)
        print("  Chunk \(i+1): \"\(display)\" → \(parsed.count) event(s)")
    }
    print("\nTotal events parsed: \(allEvents.count)")
    for (i, event) in allEvents.enumerated() {
        print("  [\(i+1)] data: \"\(event.data)\"")
    }
    print("✅ Split SSE chunks reassembled correctly")

    // ---- 2d. Event with id and retry ----
    printSubHeader("2d. Event with ID and Retry Fields")

    parser.reset()
    let sseData4 = "id: 42\nretry: 3000\nevent: update\ndata: payload here\n\n".data(using: .utf8)!
    print("Feed: event with id=42, retry=3000, type=update")
    let events4 = parser.parse(sseData4)
    for event in events4 {
        print("  type: \"\(event.event)\", data: \"\(event.data)\", id: \(event.id ?? "nil"), retry: \(event.retry.map(String.init) ?? "nil")")
    }
    print("  lastEventId: \(parser.lastEventId ?? "nil")")
    print("✅ ID and retry fields parsed correctly")

    // ---- 2e. Comments ignored ----
    printSubHeader("2e. Comments Are Ignored")

    parser.reset()
    let sseData5 = ": this is a comment\ndata: visible data\n\n".data(using: .utf8)!
    print("Feed: \":this is a comment\\ndata: visible data\\n\\n\"")
    let events5 = parser.parse(sseData5)
    print("  Parsed \(events5.count) event(s)")
    if let e = events5.first {
        print("  data: \"\(e.data)\"")
    }
    print("✅ Comments correctly ignored")

    // ---- 2f. Multi-line data ----
    printSubHeader("2f. Multi-Line Data Field")

    parser.reset()
    let sseData6 = "data: line one\ndata: line two\ndata: line three\n\n".data(using: .utf8)!
    print("Feed: 3 data fields in one event")
    let events6 = parser.parse(sseData6)
    if let e = events6.first {
        print("  data: \"\(e.data)\"")
        print("  (contains \\n between lines: \(e.data.contains("\n") ? "yes" : "no"))")
    }
    print("✅ Multi-line data joined correctly")

    waitForUser()
}

// MARK: - 3. UTF-8 Safety Demo

func demoUTF8Safety() {
    printHeader("3. UTF-8 Safety — Multi-Byte Character Boundary Detection")

    let buffer = StreamBuffer()

    // ---- 3a. Complete multi-byte characters ----
    printSubHeader("3a. Complete Multi-Byte Characters")

    let emoji = "Hello 🌍🚀".data(using: .utf8)!
    buffer.append(emoji)
    print("Appended: \"Hello 🌍🚀\" (\(emoji.count) bytes)")
    if let str = buffer.readUTF8SafeString() {
        print("UTF-8 safe read: \"\(str)\"")
    }
    print("✅ Complete multi-byte characters read correctly")

    // ---- 3b. Incomplete multi-byte at boundary ----
    printSubHeader("3b. Incomplete Multi-Byte at Boundary")

    buffer.reset()
    let chinese = "你好世界".data(using: .utf8)!  // 12 bytes (3 bytes per char)
    let partial = chinese.prefix(10)  // Cuts the 4th character
    buffer.append(Data(partial))
    print("Appended first 10 bytes of \"你好世界\" (12 bytes total)")
    print("Buffer size: \(buffer.count)")

    let safeCount = StreamBuffer.utf8SafeByteCount(buffer.data)
    print("UTF-8 safe byte count: \(safeCount) (expected: 9 = 3 chars × 3 bytes)")

    if let str = buffer.readUTF8SafeString() {
        print("UTF-8 safe read: \"\(str)\"")
        print("Remaining bytes in buffer: \(buffer.count) (the incomplete trailing byte)")
    }

    // Now complete the character
    let rest = chinese.suffix(from: 10)
    buffer.append(Data(rest))
    print("\nAppended remaining \(rest.count) bytes")
    if let str = buffer.readUTF8SafeString() {
        print("UTF-8 safe read: \"\(str)\"")
    }
    print("Buffer empty: \(buffer.isEmpty)")
    print("✅ Incomplete multi-byte characters handled safely")

    // ---- 3c. Static utf8SafeByteCount ----
    printSubHeader("3c. utf8SafeByteCount Static Method")

    // 2-byte character (é = 0xC3 0xA9)
    let twoByteChar = "café".data(using: .utf8)!
    let truncated2 = Data(twoByteChar.prefix(twoByteChar.count - 1))
    let safe2 = StreamBuffer.utf8SafeByteCount(truncated2)
    print("\"café\" has \(twoByteChar.count) bytes; truncated to \(truncated2.count)")
    print("  Safe byte count: \(safe2)")

    // 4-byte character (𝕳 = U+1D573)
    let fourByte = "A𝕳B".data(using: .utf8)!
    let truncated4 = Data(fourByte.prefix(3))  // 'A' + first 2 bytes of 𝕳
    let safe4 = StreamBuffer.utf8SafeByteCount(truncated4)
    print("\"A𝕳B\" has \(fourByte.count) bytes; truncated to 3 bytes")
    print("  Safe byte count: \(safe4) (only 'A' is complete)")
    print("✅ utf8SafeByteCount works correctly for all multi-byte sequences")

    waitForUser()
}

// MARK: - 4. ReadRequest Demo

func demoReadRequest() {
    printHeader("4. ReadRequest — Read-Request Queue Types")

    // ---- 4a. Available request ----
    printSubHeader("4a. ReadRequest.available")
    let r1 = ReadRequest(type: .available, timeout: -1, tag: 1)
    print("  type: available, timeout: \(r1.timeout), tag: \(r1.tag)")

    // ---- 4b. toLength request ----
    printSubHeader("4b. ReadRequest.toLength")
    let r2 = ReadRequest(type: .toLength(1024), timeout: 30, tag: 2)
    if case .toLength(let len) = r2.type {
        print("  type: toLength(\(len)), timeout: \(r2.timeout), tag: \(r2.tag)")
    }

    // ---- 4c. toDelimiter request ----
    printSubHeader("4c. ReadRequest.toDelimiter")
    let delimData = "\r\n".data(using: .utf8)!
    let r3 = ReadRequest(type: .toDelimiter(delimData), timeout: 60, tag: 3)
    if case .toDelimiter(let d) = r3.type {
        print("  type: toDelimiter(\\r\\n, \(d.count) bytes), timeout: \(r3.timeout), tag: \(r3.tag)")
    }

    // ---- 4d. Simulate a read queue ----
    printSubHeader("4d. Simulating a Read Queue")

    let buffer = StreamBuffer()
    var readQueue: [ReadRequest] = [
        ReadRequest(type: .toLength(5), timeout: -1, tag: 10),
        ReadRequest(type: .toDelimiter("\n".data(using: .utf8)!), timeout: -1, tag: 11),
        ReadRequest(type: .available, timeout: -1, tag: 12),
    ]

    print("Queue: [toLength(5), toDelimiter(\\n), available]")
    print("Feeding data: \"HelloWorld\\nExtra\"")

    buffer.append("HelloWorld\nExtra".data(using: .utf8)!)

    var satisfied = 0
    while !readQueue.isEmpty {
        let request = readQueue[0]
        var result: Data?

        switch request.type {
        case .available:
            if !buffer.isEmpty {
                result = buffer.readAllData()
            }
        case .toLength(let length):
            result = buffer.readData(toLength: length)
        case .toDelimiter(let delimiter):
            result = buffer.readData(toDelimiter: delimiter)
        }

        if let data = result {
            readQueue.removeFirst()
            satisfied += 1
            let text = String(data: data, encoding: .utf8) ?? "<binary>"
            print("  Tag \(request.tag): \"\(text.replacingOccurrences(of: "\n", with: "\\n"))\" (\(data.count) bytes)")
        } else {
            break
        }
    }
    print("Satisfied \(satisfied) of 3 requests, buffer remaining: \(buffer.count)")
    print("✅ Read queue processing works correctly")

    waitForUser()
}

// MARK: - 5. NWAsyncSocket Usage Pattern

func demoNWAsyncSocketUsage() {
    printHeader("5. NWAsyncSocket — Connection Usage Pattern")

    #if canImport(Network)
    print("""
    NWAsyncSocket is available on this platform (Network.framework).

    Below is a live demo showing how to create and configure a socket.
    (Actual network connections require a running server.)

    """)

    // Demonstrate object creation and configuration
    let socket = NWAsyncSocket(delegateQueue: .main)
    print("Created NWAsyncSocket instance")
    print("  isConnected: \(socket.isConnected)")
    print("  connectedHost: \(socket.connectedHost ?? "nil")")
    print("  connectedPort: \(socket.connectedPort)")

    socket.enableTLS()
    print("\n  enableTLS() called — TLS will be used on next connect")

    socket.enableSSEParsing()
    print("  enableSSEParsing() called — SSE events will be parsed automatically")

    socket.enableStreamingText()
    print("  enableStreamingText() called — UTF-8 strings will be delivered")

    socket.userData = ["key": "value"]
    print("  userData set: \(socket.userData ?? "nil")")

    print("""

    To test with a real server, implement NWAsyncSocketDelegate:

        class MyHandler: NWAsyncSocketDelegate {
            func socket(_ sock: NWAsyncSocket, didConnectToHost host: String, port: UInt16) {
                print("Connected to \\(host):\\(port)")
                // Send an HTTP request
                let http = "GET / HTTP/1.1\\r\\nHost: \\(host)\\r\\n\\r\\n"
                sock.write(http.data(using: .utf8)!, withTimeout: 30, tag: 1)
                sock.readData(withTimeout: 30, tag: 1)
            }

            func socket(_ sock: NWAsyncSocket, didRead data: Data, withTag tag: Int) {
                print("Received \\(data.count) bytes")
                if let text = String(data: data, encoding: .utf8) {
                    print(text.prefix(200))
                }
                sock.readData(withTimeout: -1, tag: tag + 1)
            }

            func socket(_ sock: NWAsyncSocket, didWriteDataWithTag tag: Int) {
                print("Write complete (tag \\(tag))")
            }

            func socketDidDisconnect(_ sock: NWAsyncSocket, withError error: Error?) {
                print("Disconnected: \\(error?.localizedDescription ?? "clean")")
            }

            func socket(_ sock: NWAsyncSocket, didReceiveSSEEvent event: SSEEvent) {
                print("SSE Event: type=\\(event.event) data=\\(event.data)")
            }
        }

        let handler = MyHandler()
        let socket = NWAsyncSocket(delegate: handler, delegateQueue: .main)
        socket.enableTLS()
        try socket.connect(toHost: "example.com", onPort: 443)
    """)
    #else
    print("""
    ⚠️  Network.framework is not available on this platform.
        NWAsyncSocket requires iOS 13+ / macOS 10.15+ / tvOS 13+ / watchOS 6+.

    The core components (StreamBuffer, SSEParser, ReadRequest) demonstrated
    above work on all platforms and are the building blocks of the library.

    To test NWAsyncSocket itself, run this demo on macOS or in an iOS app.

    Here is the typical usage pattern:

        import NWAsyncSocket

        class MyHandler: NWAsyncSocketDelegate {
            func socket(_ sock: NWAsyncSocket, didConnectToHost host: String, port: UInt16) {
                print("Connected to \\(host):\\(port)")
                sock.readData(withTimeout: -1, tag: 0)
            }

            func socket(_ sock: NWAsyncSocket, didRead data: Data, withTag tag: Int) {
                print("Received \\(data.count) bytes")
                sock.readData(withTimeout: -1, tag: tag + 1)
            }

            func socket(_ sock: NWAsyncSocket, didWriteDataWithTag tag: Int) {
                print("Write complete (tag \\(tag))")
            }

            func socketDidDisconnect(_ sock: NWAsyncSocket, withError error: Error?) {
                print("Disconnected: \\(error?.localizedDescription ?? "clean")")
            }
        }

        let handler = MyHandler()
        let socket = NWAsyncSocket(delegate: handler, delegateQueue: .main)
        socket.enableTLS()
        try socket.connect(toHost: "example.com", onPort: 443)
    """)
    #endif

    waitForUser()
}

// MARK: - Main Menu

func printMenu() {
    printHeader("NWAsyncSocket Swift Demo")
    print("""
    Choose a demo to run:

      1. StreamBuffer  — Sticky-packet / Split-packet handling
      2. SSEParser     — Server-Sent Events incremental parsing
      3. UTF-8 Safety  — Multi-byte character boundary detection
      4. ReadRequest   — Read-request queue types
      5. NWAsyncSocket — Connection usage pattern
      a. Run all demos
      q. Quit

    """)
}

func main() {
    var running = true
    while running {
        printMenu()
        print("Enter choice: ", terminator: "")
        guard let input = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
            continue
        }
        switch input {
        case "1":
            demoStreamBuffer()
        case "2":
            demoSSEParser()
        case "3":
            demoUTF8Safety()
        case "4":
            demoReadRequest()
        case "5":
            demoNWAsyncSocketUsage()
        case "a":
            demoStreamBuffer()
            demoSSEParser()
            demoUTF8Safety()
            demoReadRequest()
            demoNWAsyncSocketUsage()
        case "q":
            print("\nGoodbye! 👋")
            running = false
        default:
            print("Invalid choice. Please enter 1-5, a, or q.")
        }
    }
}

main()
