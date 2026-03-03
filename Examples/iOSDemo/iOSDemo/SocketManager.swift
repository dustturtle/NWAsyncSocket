import Foundation
import NWAsyncSocket

/// A manager that encapsulates NWAsyncSocket operations for use in SwiftUI.
///
/// Provides high-level methods for connecting, sending, receiving data, and
/// enables TLS, SSE parsing, and streaming text modes. Published properties
/// allow SwiftUI views to react to connection state and incoming data.
///
/// Usage:
/// ```swift
/// let manager = SocketManager()
/// manager.connect(host: "example.com", port: 443, useTLS: true)
/// manager.send("GET / HTTP/1.1\r\nHost: example.com\r\n\r\n")
/// ```
final class SocketManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var isConnected = false
    @Published var logs: [LogEntry] = []
    @Published var receivedData: Data = Data()
    @Published var receivedText: String = ""
    @Published var sseEvents: [SSEEvent] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
    }

    // MARK: - Private

    private var socket: NWAsyncSocket?
    private var readTag: Int = 0

    // MARK: - Connection

    /// Connect to a host and port. Optionally enable TLS, SSE parsing, and streaming text.
    func connect(host: String, port: UInt16, useTLS: Bool = false,
                 enableSSE: Bool = false, enableStreaming: Bool = false) {
        disconnect()

        let sock = NWAsyncSocket(delegate: self, delegateQueue: .main)

        if useTLS {
            sock.enableTLS()
        }
        if enableSSE {
            sock.enableSSEParsing()
        }
        if enableStreaming {
            sock.enableStreamingText()
        }

        socket = sock
        appendLog("Connecting to \(host):\(port)...")

        do {
            try sock.connect(toHost: host, onPort: port, withTimeout: 15)
        } catch {
            appendLog("❌ Connect error: \(error.localizedDescription)")
        }
    }

    /// Disconnect the current socket.
    func disconnect() {
        socket?.disconnect()
        socket = nil
    }

    /// Send a string as UTF-8 data.
    func send(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            appendLog("❌ Failed to encode text")
            return
        }
        send(data)
    }

    /// Send raw data.
    func send(_ data: Data) {
        guard let socket = socket else {
            appendLog("❌ Not connected")
            return
        }
        let tag = readTag
        readTag += 1
        socket.write(data, withTimeout: 30, tag: tag)
        appendLog("📤 Sent \(data.count) bytes (tag: \(tag))")
    }

    /// Request to read available data.
    func readData() {
        guard let socket = socket else {
            appendLog("❌ Not connected")
            return
        }
        let tag = readTag
        readTag += 1
        socket.readData(withTimeout: 30, tag: tag)
    }

    /// Clear all logs and received data.
    func clearAll() {
        logs.removeAll()
        receivedData = Data()
        receivedText = ""
        sseEvents.removeAll()
        readTag = 0
    }

    // MARK: - Private

    private func appendLog(_ message: String) {
        logs.append(LogEntry(message: message))
    }
}

// MARK: - NWAsyncSocketDelegate

extension SocketManager: NWAsyncSocketDelegate {

    func socket(_ sock: NWAsyncSocket, didConnectToHost host: String, port: UInt16) {
        isConnected = true
        appendLog("✅ Connected to \(host):\(port)")
        // Start reading
        sock.readData(withTimeout: -1, tag: readTag)
        readTag += 1
    }

    func socket(_ sock: NWAsyncSocket, didRead data: Data, withTag tag: Int) {
        receivedData.append(data)
        appendLog("📥 Received \(data.count) bytes (tag: \(tag))")
        // Continue reading
        sock.readData(withTimeout: -1, tag: readTag)
        readTag += 1
    }

    func socket(_ sock: NWAsyncSocket, didWriteDataWithTag tag: Int) {
        appendLog("✅ Write complete (tag: \(tag))")
    }

    func socketDidDisconnect(_ sock: NWAsyncSocket, withError error: Error?) {
        isConnected = false
        if let error = error {
            appendLog("🔴 Disconnected: \(error.localizedDescription)")
        } else {
            appendLog("🔴 Disconnected")
        }
    }

    func socket(_ sock: NWAsyncSocket, didReceiveSSEEvent event: SSEEvent) {
        sseEvents.append(event)
        appendLog("📡 SSE Event: type=\(event.event), data=\(event.data.prefix(100))")
    }

    func socket(_ sock: NWAsyncSocket, didReceiveString string: String) {
        receivedText += string
        appendLog("📝 Text chunk: \(string.prefix(100))")
    }
}
