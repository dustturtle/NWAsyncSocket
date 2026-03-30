# Why NWAsyncSocket? — Benefits Over CocoaAsyncSocket (GCDAsyncSocket)

[CocoaAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket) (`GCDAsyncSocket` / `GCDAsyncUdpSocket`) has served the Apple-developer community for over a decade. However, it relies on **deprecated system APIs** that Apple has been removing since iOS 13, and the repository has been effectively **unmaintained** — over 660 issues were auto-closed by a bot without being resolved. Crashes, memory leaks, and compatibility problems remain in the codebase to this day.

**NWAsyncSocket** is a modern, from-scratch replacement built entirely on Apple's [Network.framework](https://developer.apple.com/documentation/network) (`NWConnection` / `NWListener`). It offers a **GCDAsyncSocket-compatible delegate API** so migration is straightforward, while eliminating all the legacy issues documented below.

---

## 1. No More Deprecated API Warnings

CocoaAsyncSocket's TLS layer is built on **SecureTransport**, which Apple deprecated in iOS 13 / macOS 10.15 (2019). Every build now produces **30+ deprecation warnings**:

> `SSLClose`, `SSLRead`, `SSLWrite`, `SSLHandshake`, `SSLCreateContext`, `SSLSetIOFuncs`, `SSLSetConnection`, `SSLSetPeerDomainName`, `SSLSetCertificate`, `SSLSetProtocolVersionMin/Max`, `SSLSetEnabledCiphers`, `SSLCopyPeerTrust`, …
>
> — Issues [#852](https://github.com/robbiehanson/CocoaAsyncSocket/issues/852), [#756](https://github.com/robbiehanson/CocoaAsyncSocket/issues/756), [#724](https://github.com/robbiehanson/CocoaAsyncSocket/issues/724), [#693](https://github.com/robbiehanson/CocoaAsyncSocket/issues/693)

Migration to Network.framework was requested as early as **2018** ([#639](https://github.com/robbiehanson/CocoaAsyncSocket/issues/639)) and has never been implemented.

**NWAsyncSocket** uses `NWConnection` for all networking and relies on Network.framework's built-in TLS (`sec_protocol_options`) — **zero deprecation warnings** on any supported Xcode version.

---

## 2. Critical Crash Fixes

CocoaAsyncSocket has **dozens of unresolved crash reports** that affect production apps on modern iOS versions:

| Crash | Affected Versions | CocoaAsyncSocket Issues |
|-------|-------------------|------------------------|
| `EXC_BAD_ACCESS` in `closeWithError:` → `CFSocketInvalidate` (recursive lock abort) | iOS 16+ | [#846](https://github.com/robbiehanson/CocoaAsyncSocket/issues/846), [#823](https://github.com/robbiehanson/CocoaAsyncSocket/issues/823), [#803](https://github.com/robbiehanson/CocoaAsyncSocket/issues/803), [#676](https://github.com/robbiehanson/CocoaAsyncSocket/issues/676) |
| Crash from **removed** `kCFStreamNetworkServiceTypeVoIP` constant | iOS 16+ | [#801](https://github.com/robbiehanson/CocoaAsyncSocket/issues/801), [#402](https://github.com/robbiehanson/CocoaAsyncSocket/issues/402), [#361](https://github.com/robbiehanson/CocoaAsyncSocket/issues/361) |
| Double-free in `ssl_continueSSLHandshake` → `SSLHandshake` (libcoretls) | All | [#849](https://github.com/robbiehanson/CocoaAsyncSocket/issues/849) |
| `EXC_BAD_ACCESS` use-after-free (`0x5555…` poison pattern) | All | [#835](https://github.com/robbiehanson/CocoaAsyncSocket/issues/835), [#808](https://github.com/robbiehanson/CocoaAsyncSocket/issues/808) |
| `EXC_GUARD` file-descriptor guard exception | All | [#794](https://github.com/robbiehanson/CocoaAsyncSocket/issues/794) |
| `SIGTRAP` on iOS 16.1 | iOS 16+ | [#815](https://github.com/robbiehanson/CocoaAsyncSocket/issues/815), [#818](https://github.com/robbiehanson/CocoaAsyncSocket/issues/818) |
| Crash in `cfstreamThread` on iOS 15 | iOS 15+ | [#791](https://github.com/robbiehanson/CocoaAsyncSocket/issues/791), [#779](https://github.com/robbiehanson/CocoaAsyncSocket/issues/779), [#775](https://github.com/robbiehanson/CocoaAsyncSocket/issues/775) |
| Crash in `completeCurrentWrite` / `openStreams` | iOS 14.5+ | [#773](https://github.com/robbiehanson/CocoaAsyncSocket/issues/773), [#770](https://github.com/robbiehanson/CocoaAsyncSocket/issues/770), [#765](https://github.com/robbiehanson/CocoaAsyncSocket/issues/765) |

These crashes are **inherent to the CFSocket / SecureTransport architecture** and cannot be fixed without rewriting the library on a modern foundation — which is exactly what NWAsyncSocket does.

**NWAsyncSocket** avoids all of the above by using `NWConnection` exclusively. There are no `CFSocket`, no `CFStream`, no `SecureTransport` calls, and therefore **none of the associated crashes**.

---

## 3. iOS 16 / 17 / 18+ Compatibility

Starting with iOS 16, Apple **removed** the `kCFStreamNetworkServiceTypeVoIP` constant entirely. CocoaAsyncSocket references it, causing an **immediate crash at runtime** ([#801](https://github.com/robbiehanson/CocoaAsyncSocket/issues/801)). A community fix (PR [#717](https://github.com/robbiehanson/CocoaAsyncSocket/pull/717)) was submitted but **never merged** despite 9+ upvotes.

Additional iOS 18 / Xcode 16 issues have also been reported ([#842](https://github.com/robbiehanson/CocoaAsyncSocket/issues/842)), with no fixes forthcoming.

**NWAsyncSocket** supports iOS 13.0+ / macOS 10.15+ natively with Network.framework and is fully tested on the latest Xcode and OS versions.

---

## 4. No Memory Leaks

CocoaAsyncSocket has **long-standing memory leak issues** — some reported as far back as 2012–2013:

- Socket objects never deallocated — strong reference cycles ([#146](https://github.com/robbiehanson/CocoaAsyncSocket/issues/146), reported 2013)
- `writeData:` causes unbounded memory growth with large data ([#636](https://github.com/robbiehanson/CocoaAsyncSocket/issues/636))
- File descriptor leaks — sockets stuck in `CLOSE_WAIT` ([#118](https://github.com/robbiehanson/CocoaAsyncSocket/issues/118), [#52](https://github.com/robbiehanson/CocoaAsyncSocket/issues/52))
- UDP send / receive memory leaks ([#407](https://github.com/robbiehanson/CocoaAsyncSocket/issues/407), [#168](https://github.com/robbiehanson/CocoaAsyncSocket/issues/168), [#110](https://github.com/robbiehanson/CocoaAsyncSocket/issues/110))

**NWAsyncSocket** is built with ARC-friendly Swift (and ARC Objective-C), uses `NWConnection` lifecycle management, and properly cleans up all resources on disconnect.

---

## 5. Thread Safety by Design

CocoaAsyncSocket has multiple thread-safety problems:

- Recursive lock abort in `closeWithError:` ([#846](https://github.com/robbiehanson/CocoaAsyncSocket/issues/846))
- Stale data from a previous connection delivered after reconnect ([#576](https://github.com/robbiehanson/CocoaAsyncSocket/issues/576))
- `doReceive` blocking the main thread ([#379](https://github.com/robbiehanson/CocoaAsyncSocket/issues/379))
- Implicit `self` retention in blocks causing use-after-dealloc ([#208](https://github.com/robbiehanson/CocoaAsyncSocket/issues/208))

**NWAsyncSocket** runs all I/O and parsing on a dedicated internal serial `socketQueue` and dispatches delegate callbacks onto the caller-provided `delegateQueue` (typically `.main`). This architecture **eliminates race conditions by design**.

---

## 6. App Store–Ready: Privacy Manifest Included

Since Spring 2024, Apple requires a **Privacy Manifest** (`PrivacyInfo.xcprivacy`) for all frameworks distributed through the App Store. CocoaAsyncSocket does not have one ([#832](https://github.com/robbiehanson/CocoaAsyncSocket/issues/832)), which may cause **App Store rejection**.

**NWAsyncSocket** is designed for modern App Store requirements.

---

## 7. Built-in SSE (Server-Sent Events) Support

With the rise of AI / LLM streaming APIs (OpenAI, Claude, etc.), Server-Sent Events over raw TCP is an increasingly common requirement. CocoaAsyncSocket provides no SSE support.

**NWAsyncSocket** includes a **high-performance, incremental SSE parser** that:
- Parses events at the byte level — no unnecessary `String` conversions
- Handles all line-ending variants (`\r\n`, `\r`, `\n`)
- Works correctly across split TCP segments
- Tracks `lastEventId` for automatic reconnection
- Delivers parsed `SSEEvent` objects (type, data, id, retry) directly through the delegate

---

## 8. HTTP Chunked Transfer-Encoding Decoder

When connecting through proxies, CDNs, or Nginx reverse proxies, HTTP responses often use `Transfer-Encoding: chunked`. CocoaAsyncSocket leaves this entirely to the application.

**NWAsyncSocket** includes a built-in `ChunkedDecoder` that:
- Transparently decodes chunked streams
- Handles partial chunks across TCP segments
- Can be enabled with a single call: `enableChunkedDecoding()`

---

## 9. UTF-8 Boundary–Safe Streaming

When streaming text (e.g., LLM responses), TCP segment boundaries can split multi-byte UTF-8 characters, producing garbled text. CocoaAsyncSocket provides no protection against this.

**NWAsyncSocket**'s `StreamBuffer` includes `readUTF8SafeString()`, which **detects incomplete multi-byte sequences at segment boundaries** and buffers them until the full character arrives.

---

## 10. SSE Auto-Reconnect

For long-lived SSE connections, network interruptions are inevitable. CocoaAsyncSocket has no built-in reconnection mechanism.

**NWAsyncSocket** supports SSE auto-reconnect with a single call:

```swift
socket.enableSSEAutoReconnect(retryInterval: 3.0)
```

On disconnection, it preserves the `lastEventId`, schedules a reconnect, and notifies the delegate via `willAutoReconnectWithLastEventId(_:afterDelay:)`. Calling `disconnect()` explicitly cancels auto-reconnect.

---

## 11. Actively Maintained

CocoaAsyncSocket's 660+ issues were **auto-closed by a stale-issue bot**, not resolved by maintainers. Critical PRs with community support remain unmerged for years.

**NWAsyncSocket** is actively developed with:
- **87 unit tests** covering SSEParser, StreamBuffer, ReadRequest, and ChunkedDecoder
- **3 demo applications** (Swift CLI, iOS SwiftUI, iOS ObjC UIKit)
- Continuous integration via GitHub Actions
- Both **Swift** and **Objective-C** implementations

---

## Migration Compatibility

NWAsyncSocket provides a **GCDAsyncSocket-compatible API** to make migration easy:

| GCDAsyncSocket | NWAsyncSocket |
|---|---|
| `connectToHost:onPort:error:` | `connect(toHost:onPort:)` |
| `readDataWithTimeout:tag:` | `readData(withTimeout:tag:)` |
| `readDataToLength:withTimeout:tag:` | `readData(toLength:withTimeout:tag:)` |
| `readDataToData:withTimeout:tag:` | `readData(toData:withTimeout:tag:)` |
| `writeData:withTimeout:tag:` | `write(_:withTimeout:tag:)` |
| `disconnect` | `disconnect()` |
| `startTLS:` | `startTLS(tlsSettings:)` |
| `isConnected` | `isConnected` |
| `connectedHost` / `connectedPort` | `connectedHost` / `connectedPort` |
| `socket:didConnectToHost:port:` | `socket(_:didConnectToHost:port:)` |
| `socket:didReadData:withTag:` | `socket(_:didRead:withTag:)` |
| `socket:didWriteDataWithTag:` | `socket(_:didWriteDataWithTag:)` |
| `socketDidDisconnect:withError:` | `socketDidDisconnect(_:withError:)` |

---

## Summary

| Aspect | CocoaAsyncSocket | NWAsyncSocket |
|--------|-----------------|---------------|
| Foundation | CFSocket + SecureTransport (deprecated) | Network.framework (`NWConnection`) |
| TLS | 30+ deprecation warnings; crashes in TLS handshake | Native `sec_protocol_options` — zero warnings |
| iOS 16+ | Crashes from removed APIs | Fully compatible |
| Memory safety | Documented leaks & FD leaks (12+ years unresolved) | ARC-managed, clean lifecycle |
| Thread safety | Recursive locks, stale data races | Serial queue architecture |
| Privacy Manifest | Missing (App Store risk) | Modern compliance |
| SSE parsing | None | Built-in high-performance parser |
| Chunked decoding | None | Built-in `ChunkedDecoder` |
| UTF-8 safety | None | Boundary-safe streaming |
| Auto-reconnect | None | Built-in SSE auto-reconnect |
| Maintenance | 660+ issues auto-closed; unmerged PRs | Active development, 87 tests, CI |

**NWAsyncSocket is the modern, crash-free, future-proof replacement for GCDAsyncSocket.**
