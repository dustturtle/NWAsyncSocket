import SwiftUI
import NWAsyncSocket

struct SocketConnectionDemoView: View {
    @StateObject private var manager = SocketManager()
    @State private var host = "example.com"
    @State private var port = "443"
    @State private var useTLS = true
    @State private var enableSSE = false
    @State private var enableStreaming = true
    @State private var messageToSend = "GET / HTTP/1.1\r\nHost: example.com\r\nConnection: close\r\n\r\n"

    var body: some View {
        List {
            Section(header: Text("Connection Settings")) {
                HStack {
                    Text("Host")
                    Spacer()
                    TextField("Host", text: $host)
                        .multilineTextAlignment(.trailing)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                }
                HStack {
                    Text("Port")
                    Spacer()
                    TextField("Port", text: $port)
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.numberPad)
                }
                Toggle("TLS", isOn: $useTLS)
                Toggle("SSE Parsing", isOn: $enableSSE)
                Toggle("Streaming Text", isOn: $enableStreaming)
            }

            Section(header: Text("Actions")) {
                if manager.isConnected {
                    Button(role: .destructive) {
                        manager.disconnect()
                    } label: {
                        Label("Disconnect", systemImage: "xmark.circle")
                    }
                } else {
                    Button {
                        let portNum = UInt16(port) ?? 443
                        manager.connect(host: host, port: portNum,
                                        useTLS: useTLS,
                                        enableSSE: enableSSE,
                                        enableStreaming: enableStreaming)
                    } label: {
                        Label("Connect", systemImage: "play.circle")
                    }
                }
            }

            if manager.isConnected {
                Section(header: Text("Send Data")) {
                    TextEditor(text: $messageToSend)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 80)
                    Button {
                        manager.send(messageToSend)
                    } label: {
                        Label("Send", systemImage: "paperplane")
                    }
                }
            }

            if !manager.receivedText.isEmpty {
                Section(header: Text("Received Text")) {
                    ScrollView {
                        Text(manager.receivedText.prefix(2000))
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                }
            }

            if !manager.sseEvents.isEmpty {
                Section(header: Text("SSE Events (\(manager.sseEvents.count))")) {
                    ForEach(Array(manager.sseEvents.enumerated()), id: \.offset) { idx, event in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("[\(idx + 1)] type: \(event.event)")
                                .font(.system(.caption, design: .monospaced))
                            Text("data: \(event.data.prefix(200))")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Section(header: Text("Logs (\(manager.logs.count))")) {
                if manager.logs.isEmpty {
                    Text("No activity yet")
                        .foregroundColor(.secondary)
                } else {
                    Button("Clear") {
                        manager.clearAll()
                    }
                    ForEach(manager.logs.reversed()) { entry in
                        Text(entry.message)
                            .font(.system(.caption, design: .monospaced))
                    }
                }
            }
        }
        .navigationTitle("Socket Connection")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Circle()
                    .fill(manager.isConnected ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

#Preview {
    NavigationView {
        SocketConnectionDemoView()
    }
}
