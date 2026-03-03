import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Core Components")) {
                    NavigationLink(destination: StreamBufferDemoView()) {
                        Label("StreamBuffer", systemImage: "arrow.left.arrow.right")
                    }
                    NavigationLink(destination: SSEParserDemoView()) {
                        Label("SSE Parser", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    NavigationLink(destination: UTF8SafetyDemoView()) {
                        Label("UTF-8 Safety", systemImage: "textformat")
                    }
                }
                Section(header: Text("Socket")) {
                    NavigationLink(destination: SocketConnectionDemoView()) {
                        Label("Socket Connection", systemImage: "network")
                    }
                }
            }
            .navigationTitle("NWAsyncSocket Demo")
        }
        .navigationViewStyle(.stack)
    }
}

#Preview {
    ContentView()
}
