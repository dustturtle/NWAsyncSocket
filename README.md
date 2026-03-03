# NWAsyncSocket

A TCP socket networking library for iOS/macOS built on **Network.framework**, with an API modeled after **GCDAsyncSocket**. Optimized for consuming streaming data from Linux servers (LLM/AI streams in SSE format).

Available in **two versions**:
- 🟠 **Swift version** — `Sources/NWAsyncSocket/`
- 🔵 **Objective-C version** — `ObjC/NWAsyncSocketObjC/` (uses Network.framework's C API: `nw_connection_t`). Class is named **GCDAsyncSocket** for drop-in replacement of CocoaAsyncSocket.

## Features

- ✅ **GCDAsyncSocket-compatible API** — delegate-based, tag-based read/write
- ✅ **Sticky-packet handling (粘包)** — multiple messages packed in one TCP segment are correctly split
- ✅ **Split-packet handling (拆包)** — messages split across TCP segments are reassembled
- ✅ **UTF-8 boundary detection** — prevents multi-byte character corruption at segment boundaries
- ✅ **SSE parser** — built-in Server-Sent Events parser for LLM streaming (e.g. OpenAI, Claude)
- ✅ **Read-request queue** — ordered, non-blocking reads (`toLength`, `toDelimiter`, `available`)
- ✅ **TLS support** — optional TLS via `enableTLS()`
- ✅ **Streaming text mode** — UTF-8 safe string delivery via delegate

## Requirements

- iOS 13.0+ / macOS 10.15+ / tvOS 13.0+ / watchOS 6.0+
- Swift 5.9+ (for Swift version)
- Xcode 15+ (for Objective-C version)

### Why iOS 13+ instead of iOS 12?

Although `Network.framework` was introduced in iOS 12 (WWDC 2018), this library requires **iOS 13+** for the following reasons:

| Aspect | iOS 12 | iOS 13+ |
|--------|--------|---------|
| Network.framework availability | ✅ Available | ✅ Available |
| Stability & bug fixes | ❌ Known issues with `NWConnection` callbacks and memory leaks | ✅ Major fixes shipped |
| Continuous read loop reliability | ⚠️ Edge-case bugs in `NWConnection.receive()` under high-frequency reads | ✅ Stable |
| Swift runtime | ❌ Must be embedded in app bundle | ✅ Built into the OS |

**Key details:**

1. **Network.framework maturity** — Apple significantly improved `NWConnection` reliability in iOS 13, fixing known issues with callback delivery and memory management that existed in the iOS 12 initial release.
2. **Continuous read loop stability** — This library's core architecture uses a high-frequency continuous read loop (`receive()` → buffer → dequeue → `receive()`). This pattern triggers edge-case bugs on iOS 12 that were resolved in iOS 13.
3. **Swift runtime built-in** — Starting from iOS 13, the Swift runtime is bundled with the OS, which reduces app binary size and avoids runtime compatibility issues.
4. **Platform version alignment** — iOS 13 / macOS 10.15 / tvOS 13 / watchOS 6 are all from the same 2019 release cycle, ensuring a consistent and well-tested foundation across all Apple platforms.

> **Note:** If you absolutely need iOS 12 support, changing `.iOS(.v13)` to `.iOS(.v12)` in `Package.swift` will compile, but thorough testing on iOS 12 devices is strongly recommended — especially for long-lived connections and high-frequency read/write scenarios.

## Installation

### Swift Package Manager

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/dustturtle/NWAsyncSocket.git", from: "1.0.0")
]
```

### Objective-C

Copy the files from `ObjC/NWAsyncSocketObjC/` into your Xcode project. Add the `include/` directory to your Header Search Paths.

> **Drop-in replacement:** The Objective-C class is named `GCDAsyncSocket` with a `GCDAsyncSocketDelegate` protocol, so you can replace CocoaAsyncSocket's GCDAsyncSocket by swapping the imported header from `"GCDAsyncSocket.h"` (CocoaAsyncSocket) to `"GCDAsyncSocket.h"` (this library).

## Usage

### Swift Version

```swift
import NWAsyncSocket

class MyController: NWAsyncSocketDelegate {
    let socket = NWAsyncSocket(delegate: self, delegateQueue: .main)

    func connect() {
        try? socket.connect(toHost: "api.example.com", onPort: 8080)
    }

    // MARK: - Delegate

    func socket(_ sock: NWAsyncSocket, didConnectToHost host: String, port: UInt16) {
        print("Connected to \(host):\(port)")
        sock.readData(withTimeout: -1, tag: 0)
    }

    func socket(_ sock: NWAsyncSocket, didRead data: Data, withTag tag: Int) {
        print("Received \(data.count) bytes")
        sock.readData(withTimeout: -1, tag: 0)
    }

    func socket(_ sock: NWAsyncSocket, didWriteDataWithTag tag: Int) {
        print("Write complete for tag \(tag)")
    }

    func socketDidDisconnect(_ sock: NWAsyncSocket, withError error: Error?) {
        print("Disconnected: \(error?.localizedDescription ?? "clean")")
    }
}
```

#### SSE Streaming (LLM)

```swift
let socket = NWAsyncSocket(delegate: self, delegateQueue: .main)
socket.enableSSEParsing()
try socket.connect(toHost: "llm-server.example.com", onPort: 8080)

// Delegate receives parsed SSE events automatically:
func socket(_ sock: NWAsyncSocket, didReceiveSSEEvent event: SSEEvent) {
    print("Event: \(event.event), Data: \(event.data)")
}
```

#### Read Modes

```swift
// Read any available data
socket.readData(withTimeout: 30, tag: 1)

// Read exactly 1024 bytes
socket.readData(toLength: 1024, withTimeout: 30, tag: 2)

// Read until delimiter (e.g. newline)
socket.readData(toData: "\r\n".data(using: .utf8)!, withTimeout: 30, tag: 3)
```

### Objective-C Version

```objc
#import "GCDAsyncSocket.h"

@interface MyController () <GCDAsyncSocketDelegate>
@property (nonatomic, strong) GCDAsyncSocket *socket;
@end

@implementation MyController

- (void)connect {
    self.socket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                delegateQueue:dispatch_get_main_queue()];
    NSError *err = nil;
    [self.socket connectToHost:@"api.example.com" onPort:8080 error:&err];
}

- (void)socket:(GCDAsyncSocket *)sock didConnectToHost:(NSString *)host port:(uint16_t)port {
    NSLog(@"Connected to %@:%u", host, port);
    [sock readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didReadData:(NSData *)data withTag:(long)tag {
    NSLog(@"Received %lu bytes", (unsigned long)data.length);
    [sock readDataWithTimeout:-1 tag:0];
}

- (void)socket:(GCDAsyncSocket *)sock didWriteDataWithTag:(long)tag {
    NSLog(@"Write complete for tag %ld", tag);
}

- (void)socketDidDisconnect:(GCDAsyncSocket *)sock withError:(NSError *)error {
    NSLog(@"Disconnected: %@", error.localizedDescription);
}

@end
```

#### SSE Streaming (LLM) — Objective-C

```objc
GCDAsyncSocket *socket = [[GCDAsyncSocket alloc] initWithDelegate:self
                                                     delegateQueue:dispatch_get_main_queue()];
[socket enableSSEParsing];
[socket connectToHost:@"llm-server.example.com" onPort:8080 error:nil];

// Optional delegate method:
- (void)socket:(GCDAsyncSocket *)sock didReceiveSSEEvent:(NWSSEEvent *)event {
    NSLog(@"Event: %@ Data: %@", event.event, event.data);
}
```

## Architecture

```
┌─────────────────────────────────────────────────┐
│                   Your App                       │
│              (ViewController)                    │
├─────────────────────────────────────────────────┤
│           NWAsyncSocket / GCDAsyncSocket          │
│  ┌──────────────┐  ┌────────────┐  ┌──────────┐│
│  │  Read Queue   │  │   Buffer   │  │SSE Parser││
│  │ (ReadRequest) │  │(StreamBuf) │  │          ││
│  └──────┬───────┘  └──────┬─────┘  └────┬─────┘│
│         │                 │              │       │
│  ┌──────▼─────────────────▼──────────────▼─────┐│
│  │         Continuous Read Loop                 ││
│  │    (reads → buffer → dequeue → delegate)     ││
│  └──────────────────┬──────────────────────────┘│
├─────────────────────┼───────────────────────────┤
│         NWConnection / nw_connection_t           │
│            (Network.framework)                   │
├─────────────────────┼───────────────────────────┤
│                  TCP/IP                          │
│              (Linux Server)                      │
└─────────────────────────────────────────────────┘
```

## File Structure

```
NWAsyncSocket/
├── Package.swift                          # SPM configuration
├── README.md
├── Sources/NWAsyncSocket/                 # Swift version
│   ├── NWAsyncSocket.swift                # Main socket class (NWConnection)
│   ├── NWAsyncSocketDelegate.swift        # Delegate protocol
│   ├── StreamBuffer.swift                 # Byte buffer with UTF-8 safety
│   ├── SSEParser.swift                    # SSE event parser
│   └── ReadRequest.swift                  # Read request queue model
├── Examples/iOSDemo/                      # iOS SwiftUI demo app
│   ├── iOSDemo.xcodeproj                 # Open in Xcode to run
│   └── iOSDemo/
│       ├── iOSDemoApp.swift              # App entry point
│       ├── ContentView.swift             # Main navigation
│       ├── SocketManager.swift           # Encapsulated socket operations
│       └── Views/                        # Feature demo views
├── Examples/iOSDemoObjC/                  # iOS UIKit demo app (Objective-C)
│   ├── iOSDemoObjC.xcodeproj             # Open in Xcode to run
│   └── iOSDemoObjC/
│       ├── main.m                        # App entry point
│       ├── AppDelegate.h/.m              # App delegate
│       ├── MainViewController.h/.m       # Main navigation
│       ├── SocketManager.h/.m            # Encapsulated socket operations
│       └── Views/                        # Feature demo views
├── Examples/SwiftDemo/                    # Swift interactive demo (CLI)
│   └── main.swift                         # Run: swift run SwiftDemo
├── ObjC/NWAsyncSocketObjC/                # Objective-C version
│   ├── include/                           # Public headers
│   │   ├── GCDAsyncSocket.h               # Main class (drop-in replacement)
│   │   ├── GCDAsyncSocketDelegate.h       # Delegate protocol
│   │   ├── NWStreamBuffer.h
│   │   ├── NWSSEParser.h
│   │   └── NWReadRequest.h
│   ├── GCDAsyncSocket.m                   # Main socket (nw_connection_t C API)
│   ├── NWStreamBuffer.m
│   ├── NWSSEParser.m
│   └── NWReadRequest.m
├── ObjC/ObjCDemo/                         # Objective-C interactive demo
│   └── main.m                             # Build with clang (see Demo section)
├── ObjC/NWAsyncSocketObjCTests/           # ObjC XCTest cases
│   ├── NWStreamBufferTests.m
│   ├── NWSSEParserTests.m
│   └── NWReadRequestTests.m
└── Tests/NWAsyncSocketTests/              # Swift XCTest cases (71 tests)
    ├── StreamBufferTests.swift
    ├── SSEParserTests.swift
    └── ReadRequestTests.swift
```

## Testing

### Swift Tests (run on Linux & macOS)

```bash
swift test
```

71 tests covering:
- StreamBuffer: basic ops, read-to-length, read-to-delimiter, sticky/split packets, UTF-8 safety
- SSEParser: single/multi events, CRLF/CR/LF, split chunks, LLM simulation, comments, edge cases
- ReadRequest: all request types

### Objective-C Tests (run in Xcode on macOS)

Add the ObjC source and test files to an Xcode project and run the XCTest test suite.

## Demo

Interactive demos are provided to help you verify all core components.

### iOS App Demo — Swift (Recommended)

A complete SwiftUI iOS app is included at `Examples/iOSDemo/`. Open `Examples/iOSDemo/iOSDemo.xcodeproj` in Xcode and run on a simulator or device.

The app demonstrates all core components with an interactive UI:

- **StreamBuffer** — sticky-packet / split-packet handling, delimiter-based reads
- **SSE Parser** — single/multi/split SSE events, LLM streaming simulation
- **UTF-8 Safety** — multi-byte character boundary detection
- **Socket Connection** — connect/disconnect, send/receive, TLS, SSE, streaming text

The app includes a `SocketManager` class that encapsulates all NWAsyncSocket operations into a clean, SwiftUI-friendly `ObservableObject` with `@Published` properties.

### iOS App Demo — Objective-C

A complete UIKit iOS app is included at `Examples/iOSDemoObjC/`. Open `Examples/iOSDemoObjC/iOSDemoObjC.xcodeproj` in Xcode and run on a simulator or device.

The app demonstrates the same core components as the Swift demo using the Objective-C SDK:

- **StreamBuffer** — sticky-packet / split-packet handling, delimiter-based reads
- **SSE Parser** — single/multi/split SSE events, LLM streaming simulation
- **UTF-8 Safety** — multi-byte character boundary detection
- **Socket Connection** — connect/disconnect, send/receive, TLS, SSE, streaming text

The app includes a `SocketManager` class that encapsulates all GCDAsyncSocket operations with delegate callbacks and `NSNotification`-based UI updates. The ObjC SDK source files are referenced directly from `ObjC/NWAsyncSocketObjC/`.

### Swift Demo (CLI)

Run the interactive Swift demo via SPM:

```bash
swift run SwiftDemo
```

The demo menu lets you test each component individually or run all at once:

1. **StreamBuffer** — sticky-packet / split-packet handling, delimiter-based reads
2. **SSEParser** — single/multi/split SSE events, LLM streaming simulation, ID/retry fields
3. **UTF-8 Safety** — multi-byte character boundary detection, incomplete sequence handling
4. **ReadRequest** — all read-request queue types with simulated queue processing
5. **NWAsyncSocket** — connection setup and delegate usage pattern (Network.framework only)

### Objective-C Demo (CLI)

Build the ObjC CLI demo on macOS:

```bash
clang -framework Foundation \
      -I ObjC/NWAsyncSocketObjC/include \
      ObjC/NWAsyncSocketObjC/NWStreamBuffer.m \
      ObjC/NWAsyncSocketObjC/NWSSEParser.m \
      ObjC/NWAsyncSocketObjC/NWReadRequest.m \
      ObjC/NWAsyncSocketObjC/GCDAsyncSocket.m \
      ObjC/ObjCDemo/main.m \
      -o ObjCDemo
./ObjCDemo
```

The ObjC demo provides the same interactive menu and covers:

1. **NWStreamBuffer** — sticky-packet / split-packet handling, delimiter-based reads
2. **NWSSEParser** — single/multi/split SSE events, LLM streaming simulation, ID/retry fields
3. **UTF-8 Safety** — multi-byte boundary detection with `utf8SafeByteCountForData:`
4. **NWReadRequest** — all read-request queue types with simulated queue processing
5. **GCDAsyncSocket** — connection setup, delegate implementation, and usage pattern

## API Compatibility with GCDAsyncSocket

| GCDAsyncSocket (CocoaAsyncSocket) | NWAsyncSocket (Swift) | GCDAsyncSocket (this library) |
|---|---|---|
| `initWithDelegate:delegateQueue:` | `init(delegate:delegateQueue:)` | `initWithDelegate:delegateQueue:` |
| `connectToHost:onPort:error:` | `connect(toHost:onPort:)` | `connectToHost:onPort:error:` |
| `readDataWithTimeout:tag:` | `readData(withTimeout:tag:)` | `readDataWithTimeout:tag:` |
| `readDataToLength:withTimeout:tag:` | `readData(toLength:withTimeout:tag:)` | `readDataToLength:withTimeout:tag:` |
| `readDataToData:withTimeout:tag:` | `readData(toData:withTimeout:tag:)` | `readDataToData:withTimeout:tag:` |
| `writeData:withTimeout:tag:` | `write(_:withTimeout:tag:)` | `writeData:withTimeout:tag:` |
| `disconnect` | `disconnect()` | `disconnect` |
| `isConnected` | `isConnected` | `isConnected` |

## License

MIT
