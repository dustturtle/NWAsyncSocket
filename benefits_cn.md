# 为什么选择 NWAsyncSocket？—— 相比 CocoaAsyncSocket (GCDAsyncSocket) 的优势

[CocoaAsyncSocket](https://github.com/robbiehanson/CocoaAsyncSocket)（`GCDAsyncSocket` / `GCDAsyncUdpSocket`）在 Apple 开发社区已服务超过十年。然而，它依赖的**系统 API 已被 Apple 弃用**（自 iOS 13 起），并且该仓库实际上已**停止维护** —— 超过 660 个 issue 被机器人自动关闭，而非被修复。崩溃、内存泄漏和兼容性问题至今仍存在于代码中。

**NWAsyncSocket** 是一个基于 Apple [Network.framework](https://developer.apple.com/documentation/network)（`NWConnection` / `NWListener`）从零构建的现代化替代品。它提供与 **GCDAsyncSocket 兼容的 delegate API**，使迁移变得简单直接，同时消除了以下所有历史遗留问题。

---

## 1. 彻底告别废弃 API 警告

CocoaAsyncSocket 的 TLS 层构建在 **SecureTransport** 之上，该框架自 iOS 13 / macOS 10.15（2019年）起已被 Apple 弃用。每次构建都会产生 **30+ 个弃用警告**：

> `SSLClose`、`SSLRead`、`SSLWrite`、`SSLHandshake`、`SSLCreateContext`、`SSLSetIOFuncs`、`SSLSetConnection`、`SSLSetPeerDomainName`、`SSLSetCertificate`、`SSLSetProtocolVersionMin/Max`、`SSLSetEnabledCiphers`、`SSLCopyPeerTrust`……
>
> — Issues [#852](https://github.com/robbiehanson/CocoaAsyncSocket/issues/852)、[#756](https://github.com/robbiehanson/CocoaAsyncSocket/issues/756)、[#724](https://github.com/robbiehanson/CocoaAsyncSocket/issues/724)、[#693](https://github.com/robbiehanson/CocoaAsyncSocket/issues/693)

迁移至 Network.framework 的请求早在 **2018 年**就已提出（[#639](https://github.com/robbiehanson/CocoaAsyncSocket/issues/639)），但从未实现。

**NWAsyncSocket** 使用 `NWConnection` 进行所有网络通信，依赖 Network.framework 内置的 TLS（`sec_protocol_options`）—— 在任何支持的 Xcode 版本上**零弃用警告**。

---

## 2. 修复关键性崩溃问题

CocoaAsyncSocket 存在**数十个未解决的崩溃报告**，影响现代 iOS 版本上的生产环境应用：

| 崩溃类型 | 影响版本 | CocoaAsyncSocket Issues |
|---------|---------|------------------------|
| `closeWithError:` → `CFSocketInvalidate` 中的 `EXC_BAD_ACCESS`（递归锁中止） | iOS 16+ | [#846](https://github.com/robbiehanson/CocoaAsyncSocket/issues/846)、[#823](https://github.com/robbiehanson/CocoaAsyncSocket/issues/823)、[#803](https://github.com/robbiehanson/CocoaAsyncSocket/issues/803)、[#676](https://github.com/robbiehanson/CocoaAsyncSocket/issues/676) |
| 已**删除**的 `kCFStreamNetworkServiceTypeVoIP` 常量导致崩溃 | iOS 16+ | [#801](https://github.com/robbiehanson/CocoaAsyncSocket/issues/801)、[#402](https://github.com/robbiehanson/CocoaAsyncSocket/issues/402)、[#361](https://github.com/robbiehanson/CocoaAsyncSocket/issues/361) |
| `ssl_continueSSLHandshake` → `SSLHandshake` 中的 double-free（libcoretls） | 全版本 | [#849](https://github.com/robbiehanson/CocoaAsyncSocket/issues/849) |
| `EXC_BAD_ACCESS` 释放后使用（`0x5555…` 毒化模式） | 全版本 | [#835](https://github.com/robbiehanson/CocoaAsyncSocket/issues/835)、[#808](https://github.com/robbiehanson/CocoaAsyncSocket/issues/808) |
| `EXC_GUARD` 文件描述符保护异常 | 全版本 | [#794](https://github.com/robbiehanson/CocoaAsyncSocket/issues/794) |
| iOS 16.1 上的 `SIGTRAP` | iOS 16+ | [#815](https://github.com/robbiehanson/CocoaAsyncSocket/issues/815)、[#818](https://github.com/robbiehanson/CocoaAsyncSocket/issues/818) |
| iOS 15 上 `cfstreamThread` 崩溃 | iOS 15+ | [#791](https://github.com/robbiehanson/CocoaAsyncSocket/issues/791)、[#779](https://github.com/robbiehanson/CocoaAsyncSocket/issues/779)、[#775](https://github.com/robbiehanson/CocoaAsyncSocket/issues/775) |
| `completeCurrentWrite` / `openStreams` 崩溃 | iOS 14.5+ | [#773](https://github.com/robbiehanson/CocoaAsyncSocket/issues/773)、[#770](https://github.com/robbiehanson/CocoaAsyncSocket/issues/770)、[#765](https://github.com/robbiehanson/CocoaAsyncSocket/issues/765) |

这些崩溃是 **CFSocket / SecureTransport 架构固有的**，不重写整个库就无法修复 —— 而这正是 NWAsyncSocket 所做的事情。

**NWAsyncSocket** 通过完全使用 `NWConnection` 避免了上述所有问题。没有 `CFSocket`、没有 `CFStream`、没有 `SecureTransport` 调用，因此**不存在相关崩溃**。

---

## 3. iOS 16 / 17 / 18+ 完全兼容

从 iOS 16 开始，Apple **彻底移除**了 `kCFStreamNetworkServiceTypeVoIP` 常量。CocoaAsyncSocket 引用了该常量，导致**运行时立即崩溃**（[#801](https://github.com/robbiehanson/CocoaAsyncSocket/issues/801)）。社区提交了修复 PR（[#717](https://github.com/robbiehanson/CocoaAsyncSocket/pull/717)），但尽管获得 9+ 个赞，**始终未被合并**。

此外，iOS 18 / Xcode 16 上也报告了新的问题（[#842](https://github.com/robbiehanson/CocoaAsyncSocket/issues/842)），但没有修复计划。

**NWAsyncSocket** 原生支持 iOS 13.0+ / macOS 10.15+，使用 Network.framework，已在最新的 Xcode 和操作系统版本上完成测试。

---

## 4. 无内存泄漏

CocoaAsyncSocket 存在**长期未修复的内存泄漏问题** —— 部分问题早在 2012–2013 年就已报告：

- Socket 对象永远不会被释放 —— 强引用循环（[#146](https://github.com/robbiehanson/CocoaAsyncSocket/issues/146)，2013 年报告）
- `writeData:` 大数据写入导致内存无限增长（[#636](https://github.com/robbiehanson/CocoaAsyncSocket/issues/636)）
- 文件描述符泄漏 —— Socket 停留在 `CLOSE_WAIT` 状态（[#118](https://github.com/robbiehanson/CocoaAsyncSocket/issues/118)、[#52](https://github.com/robbiehanson/CocoaAsyncSocket/issues/52)）
- UDP 发送/接收内存泄漏（[#407](https://github.com/robbiehanson/CocoaAsyncSocket/issues/407)、[#168](https://github.com/robbiehanson/CocoaAsyncSocket/issues/168)、[#110](https://github.com/robbiehanson/CocoaAsyncSocket/issues/110)）

**NWAsyncSocket** 使用 ARC 友好的 Swift（以及 ARC Objective-C）构建，利用 `NWConnection` 生命周期管理，在断开连接时正确清理所有资源。

---

## 5. 线程安全设计

CocoaAsyncSocket 存在多个线程安全问题：

- `closeWithError:` 中的递归锁中止（[#846](https://github.com/robbiehanson/CocoaAsyncSocket/issues/846)）
- 重连后收到上一次连接的过时数据（[#576](https://github.com/robbiehanson/CocoaAsyncSocket/issues/576)）
- `doReceive` 阻塞主线程（[#379](https://github.com/robbiehanson/CocoaAsyncSocket/issues/379)）
- Block 隐式持有 `self` 导致释放后使用（[#208](https://github.com/robbiehanson/CocoaAsyncSocket/issues/208)）

**NWAsyncSocket** 在专用的内部串行 `socketQueue` 上运行所有 I/O 和解析操作，将 delegate 回调分发到调用方提供的 `delegateQueue`（通常是 `.main`）。这种架构**从设计上消除了竞态条件**。

---

## 6. 符合 App Store 要求：隐私清单

自 2024 年春季起，Apple 要求所有通过 App Store 分发的框架必须包含 **Privacy Manifest**（`PrivacyInfo.xcprivacy`）。CocoaAsyncSocket 没有提供（[#832](https://github.com/robbiehanson/CocoaAsyncSocket/issues/832)），可能导致 **App Store 审核被拒**。

**NWAsyncSocket** 针对现代 App Store 要求进行了设计。

---

## 7. 内置 SSE（Server-Sent Events）支持

随着 AI / LLM 流式 API（OpenAI、Claude 等）的兴起，基于原始 TCP 的 Server-Sent Events 成为越来越常见的需求。CocoaAsyncSocket 不提供任何 SSE 支持。

**NWAsyncSocket** 包含**高性能、增量式 SSE 解析器**：
- 在字节级别解析事件 —— 避免不必要的 `String` 转换
- 处理所有换行符变体（`\r\n`、`\r`、`\n`）
- 正确处理跨 TCP 分段的拆分数据
- 追踪 `lastEventId` 以支持自动重连
- 通过 delegate 直接交付解析后的 `SSEEvent` 对象（type、data、id、retry）

---

## 8. HTTP 分块传输编码解码器

通过代理、CDN 或 Nginx 反向代理连接时，HTTP 响应通常使用 `Transfer-Encoding: chunked`。CocoaAsyncSocket 将此完全交给应用层处理。

**NWAsyncSocket** 内置 `ChunkedDecoder`：
- 透明解码分块流
- 处理跨 TCP 分段的不完整块
- 只需一行代码即可启用：`enableChunkedDecoding()`

---

## 9. UTF-8 边界安全的流式传输

在流式传输文本（如 LLM 响应）时，TCP 分段边界可能会将多字节 UTF-8 字符拆分，导致文本乱码。CocoaAsyncSocket 不提供任何保护机制。

**NWAsyncSocket** 的 `StreamBuffer` 包含 `readUTF8SafeString()`，能够**检测分段边界上的不完整多字节序列**，并将其缓冲直到完整字符到达。

---

## 10. SSE 自动重连

对于长连接 SSE 场景，网络中断是不可避免的。CocoaAsyncSocket 没有内置重连机制。

**NWAsyncSocket** 支持 SSE 自动重连，只需一行代码：

```swift
socket.enableSSEAutoReconnect(retryInterval: 3.0)
```

断开连接时，它会保留 `lastEventId`，调度重连，并通过 `willAutoReconnectWithLastEventId(_:afterDelay:)` 通知 delegate。显式调用 `disconnect()` 会取消自动重连。

---

## 11. 持续活跃维护

CocoaAsyncSocket 的 660+ 个 issue 被**过期 issue 机器人自动关闭**，而非由维护者解决。具有社区支持的关键 PR 多年未被合并。

**NWAsyncSocket** 正在积极开发中：
- **87 个单元测试**，覆盖 SSEParser、StreamBuffer、ReadRequest 和 ChunkedDecoder
- **3 个示例应用**（Swift CLI、iOS SwiftUI、iOS ObjC UIKit）
- 通过 GitHub Actions 持续集成
- 同时提供 **Swift** 和 **Objective-C** 实现

---

## 迁移兼容性

NWAsyncSocket 提供**与 GCDAsyncSocket 兼容的 API**，使迁移变得简单：

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

## 总结对比

| 方面 | CocoaAsyncSocket | NWAsyncSocket |
|------|-----------------|---------------|
| 基础架构 | CFSocket + SecureTransport（已弃用） | Network.framework（`NWConnection`） |
| TLS | 30+ 弃用警告；TLS 握手崩溃 | 原生 `sec_protocol_options` —— 零警告 |
| iOS 16+ | 因已删除 API 崩溃 | 完全兼容 |
| 内存安全 | 已知泄漏和 FD 泄漏（12+ 年未修复） | ARC 管理，完整的生命周期管理 |
| 线程安全 | 递归锁、过时数据竞争 | 串行队列架构 |
| 隐私清单 | 缺失（App Store 风险） | 符合现代合规要求 |
| SSE 解析 | 无 | 内置高性能解析器 |
| 分块解码 | 无 | 内置 `ChunkedDecoder` |
| UTF-8 安全 | 无 | 边界安全的流式传输 |
| 自动重连 | 无 | 内置 SSE 自动重连 |
| 维护状态 | 660+ issue 被机器人自动关闭；PR 未合并 | 积极开发中，87 个测试，CI 集成 |

**NWAsyncSocket 是 GCDAsyncSocket 的现代化、无崩溃、面向未来的替代方案。**
