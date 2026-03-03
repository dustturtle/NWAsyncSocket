import SwiftUI
import NWAsyncSocket

struct UTF8SafetyDemoView: View {
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
                    Text("Tap \"Run All\" to demonstrate UTF-8 boundary safety: complete multi-byte characters, incomplete boundary detection, and safe byte counting.")
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
        .navigationTitle("UTF-8 Safety")
        .toolbar {
            Button("Run All") { runAllDemos() }
        }
    }

    private func runAllDemos() {
        results.removeAll()
        demoCompleteMultiByte()
        demoIncompleteBoundary()
        demoSafeByteCount()
    }

    private func demoCompleteMultiByte() {
        let buffer = StreamBuffer()
        let emoji = "Hello 🌍🚀".data(using: .utf8)!
        buffer.append(emoji)
        let str = buffer.readUTF8SafeString()

        let success = str == "Hello 🌍🚀"
        let detail = """
        Input: "Hello 🌍🚀" (\(emoji.count) bytes)
        UTF-8 safe read: "\(str ?? "nil")"
        """
        results.append(DemoResult(title: "Complete Multi-Byte Characters", detail: detail, success: success))
    }

    private func demoIncompleteBoundary() {
        let buffer = StreamBuffer()
        let chinese = "你好世界".data(using: .utf8)!  // 12 bytes (3 per char)
        let partial = Data(chinese.prefix(10))  // Cuts 4th character
        buffer.append(partial)

        let safeCount = StreamBuffer.utf8SafeByteCount(buffer.data)
        let str1 = buffer.readUTF8SafeString()
        let remaining1 = buffer.count

        // Complete the character
        buffer.append(Data(chinese.suffix(from: 10)))
        let str2 = buffer.readUTF8SafeString()

        let success = safeCount == 9 && str1 == "你好世" && str2 == "界" && buffer.isEmpty
        let detail = """
        "你好世界" = \(chinese.count) bytes (3 bytes/char)
        Truncated to 10 bytes:
          Safe byte count: \(safeCount) (3 chars × 3 bytes)
          First read: "\(str1 ?? "nil")"
          Remaining: \(remaining1) byte(s)
        After appending final \(chinese.count - 10) bytes:
          Second read: "\(str2 ?? "nil")"
          Buffer empty: \(buffer.isEmpty)
        """
        results.append(DemoResult(title: "Incomplete Boundary Detection", detail: detail, success: success))
    }

    private func demoSafeByteCount() {
        // 2-byte character (é = 0xC3 0xA9)
        let cafe = "café".data(using: .utf8)!
        let truncated2 = Data(cafe.prefix(cafe.count - 1))
        let safe2 = StreamBuffer.utf8SafeByteCount(truncated2)

        // 4-byte character (𝕳 = U+1D573)
        let fourByte = "A𝕳B".data(using: .utf8)!
        let truncated4 = Data(fourByte.prefix(3))
        let safe4 = StreamBuffer.utf8SafeByteCount(truncated4)

        let success = safe2 == cafe.count - 2 && safe4 == 1
        let detail = """
        "café" → \(cafe.count) bytes, truncated to \(truncated2.count):
          Safe count: \(safe2) (excludes incomplete é)

        "A𝕳B" → \(fourByte.count) bytes, truncated to 3:
          Safe count: \(safe4) (only 'A' is complete)
        """
        results.append(DemoResult(title: "utf8SafeByteCount", detail: detail, success: success))
    }
}

#Preview {
    NavigationView {
        UTF8SafetyDemoView()
    }
}
