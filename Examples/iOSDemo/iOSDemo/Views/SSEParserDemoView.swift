import SwiftUI
import NWAsyncSocket

struct SSEParserDemoView: View {
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
                    Text("Tap \"Run All\" to demonstrate SSE parsing: single events, multiple events, LLM streaming simulation, and special fields.")
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
        .navigationTitle("SSE Parser")
        .toolbar {
            Button("Run All") { runAllDemos() }
        }
    }

    private func runAllDemos() {
        results.removeAll()
        demoSingleEvent()
        demoMultipleEvents()
        demoLLMStreaming()
        demoIdRetry()
        demoMultiLineData()
    }

    private func demoSingleEvent() {
        let parser = SSEParser()
        let data = "event: chat\ndata: Hello from the server!\n\n".data(using: .utf8)!
        let events = parser.parse(data)

        let success = events.count == 1 && events.first?.event == "chat"
        let detail = """
        Input: "event: chat\\ndata: Hello from the server!\\n\\n"
        Parsed \(events.count) event(s):
        \(events.map { "  type: \($0.event), data: \($0.data)" }.joined(separator: "\n"))
        """
        results.append(DemoResult(title: "Single SSE Event", detail: detail, success: success))
    }

    private func demoMultipleEvents() {
        let parser = SSEParser()
        let data = "data: first\n\ndata: second\n\nevent: custom\ndata: third\n\n".data(using: .utf8)!
        let events = parser.parse(data)

        let success = events.count == 3
        let detail = """
        Parsed \(events.count) events from one chunk:
        \(events.enumerated().map { "  [\($0.offset + 1)] type: \($0.element.event), data: \($0.element.data)" }.joined(separator: "\n"))
        """
        results.append(DemoResult(title: "Multiple Events in One Chunk", detail: detail, success: success))
    }

    private func demoLLMStreaming() {
        let parser = SSEParser()
        let chunks = [
            "data: {\"tok",
            "en\": \"Hel\"}\n",
            "\ndata: {\"token\"",
            ": \"lo\"}\n\ndata",
            ": {\"token\": \" World\"}\n\n"
        ]

        var allEvents: [SSEEvent] = []
        var chunkDetails: [String] = []
        for (i, chunk) in chunks.enumerated() {
            let parsed = parser.parse(chunk)
            allEvents.append(contentsOf: parsed)
            let display = chunk.replacingOccurrences(of: "\n", with: "\\n")
            chunkDetails.append("  Chunk \(i + 1): \"\(display)\" → \(parsed.count) event(s)")
        }

        let success = allEvents.count == 3
        let detail = """
        Fed \(chunks.count) partial chunks:
        \(chunkDetails.joined(separator: "\n"))
        Total events: \(allEvents.count)
        \(allEvents.enumerated().map { "  [\($0.offset + 1)] \($0.element.data)" }.joined(separator: "\n"))
        """
        results.append(DemoResult(title: "LLM Streaming Simulation", detail: detail, success: success))
    }

    private func demoIdRetry() {
        let parser = SSEParser()
        let data = "id: 42\nretry: 3000\nevent: update\ndata: payload\n\n".data(using: .utf8)!
        let events = parser.parse(data)

        let event = events.first
        let success = event?.id == "42" && event?.retry == 3000 && event?.event == "update"
        let detail = """
        Input: "id: 42\\nretry: 3000\\nevent: update\\ndata: payload\\n\\n"
        type: \(event?.event ?? "nil")
        data: \(event?.data ?? "nil")
        id: \(event?.id ?? "nil")
        retry: \(event?.retry.map(String.init) ?? "nil")
        lastEventId: \(parser.lastEventId ?? "nil")
        """
        results.append(DemoResult(title: "ID and Retry Fields", detail: detail, success: success))
    }

    private func demoMultiLineData() {
        let parser = SSEParser()
        let data = "data: line one\ndata: line two\ndata: line three\n\n".data(using: .utf8)!
        let events = parser.parse(data)

        let event = events.first
        let success = event?.data == "line one\nline two\nline three"
        let detail = """
        Input: 3 data fields in one event
        data: "\(event?.data ?? "nil")"
        Contains newlines: \(event?.data.contains("\n") == true ? "yes" : "no")
        """
        results.append(DemoResult(title: "Multi-Line Data", detail: detail, success: success))
    }
}

#Preview {
    NavigationView {
        SSEParserDemoView()
    }
}
