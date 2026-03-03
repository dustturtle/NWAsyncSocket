import SwiftUI
import NWAsyncSocket

struct StreamBufferDemoView: View {
    @State private var results: [DemoResult] = []

    struct DemoResult: Identifiable {
        let id = UUID()
        let title: String
        let detail: String
        let success: Bool
    }

    var body: some View {
        List {
            if results.isEmpty {
                Section {
                    Text("Tap \"Run All\" to demonstrate StreamBuffer capabilities: sticky-packet splitting, split-packet reassembly, delimiter-based reads, and read-all.")
                        .foregroundColor(.secondary)
                }
            }
            ForEach(results) { result in
                Section(header: Text(result.title)) {
                    Text(result.detail)
                        .font(.system(.body, design: .monospaced))
                    HStack {
                        Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundColor(result.success ? .green : .red)
                        Text(result.success ? "Passed" : "Failed")
                    }
                }
            }
        }
        .navigationTitle("StreamBuffer")
        .toolbar {
            Button("Run All") { runAllDemos() }
        }
    }

    private func runAllDemos() {
        results.removeAll()
        demoStickyPacket()
        demoSplitPacket()
        demoDelimiterRead()
        demoReadAll()
    }

    private func demoStickyPacket() {
        let buffer = StreamBuffer()
        let data = "Hello\r\nWorld\r\nFoo\r\n".data(using: .utf8)!
        buffer.append(data)

        let delimiter = "\r\n".data(using: .utf8)!
        var messages: [String] = []
        while let chunk = buffer.readData(toDelimiter: delimiter) {
            if let text = String(data: chunk, encoding: .utf8) {
                messages.append(text)
            }
        }

        let success = messages.count == 3
        let detail = """
        Input: "Hello\\r\\nWorld\\r\\nFoo\\r\\n"
        Parsed \(messages.count) messages:
        \(messages.enumerated().map { "  [\($0.offset + 1)] \($0.element.replacingOccurrences(of: "\r\n", with: "\\r\\n"))" }.joined(separator: "\n"))
        Remaining: \(buffer.count) bytes
        """
        results.append(DemoResult(title: "Sticky Packet (粘包)", detail: detail, success: success))
    }

    private func demoSplitPacket() {
        let buffer = StreamBuffer()
        buffer.append("Hel".data(using: .utf8)!)
        let first = buffer.readData(toLength: 11)

        buffer.append("lo World".data(using: .utf8)!)
        let second = buffer.readData(toLength: 11)

        let text = second.flatMap { String(data: $0, encoding: .utf8) }
        let success = first == nil && text == "Hello World"
        let detail = """
        Part 1: "Hel" → read 11 bytes: \(first == nil ? "nil (waiting)" : "got data")
        Part 2: "lo World" → read 11 bytes: "\(text ?? "nil")"
        """
        results.append(DemoResult(title: "Split Packet (拆包)", detail: detail, success: success))
    }

    private func demoDelimiterRead() {
        let buffer = StreamBuffer()
        buffer.append("key1=value1&key2=value2&key3=value3".data(using: .utf8)!)

        let amp = "&".data(using: .utf8)!
        var pairs: [String] = []
        while let data = buffer.readData(toDelimiter: amp) {
            if let text = String(data: data, encoding: .utf8) {
                pairs.append(text)
            }
        }
        let remaining = buffer.readAllData()
        if !remaining.isEmpty, let text = String(data: remaining, encoding: .utf8) {
            pairs.append(text)
        }

        let success = pairs.count == 3
        let detail = """
        Input: "key1=value1&key2=value2&key3=value3"
        Parsed \(pairs.count) pairs:
        \(pairs.map { "  \($0)" }.joined(separator: "\n"))
        """
        results.append(DemoResult(title: "Delimiter-Based Read", detail: detail, success: success))
    }

    private func demoReadAll() {
        let buffer = StreamBuffer()
        buffer.append("Part A ".data(using: .utf8)!)
        buffer.append("Part B ".data(using: .utf8)!)
        buffer.append("Part C".data(using: .utf8)!)
        let all = buffer.readAllData()
        let text = String(data: all, encoding: .utf8) ?? ""

        let success = text == "Part A Part B Part C" && buffer.isEmpty
        let detail = """
        Appended: "Part A " + "Part B " + "Part C"
        readAllData: "\(text)"
        Buffer empty: \(buffer.isEmpty)
        """
        results.append(DemoResult(title: "Read All Data", detail: detail, success: success))
    }
}

#Preview {
    NavigationView {
        StreamBufferDemoView()
    }
}
