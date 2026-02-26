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
