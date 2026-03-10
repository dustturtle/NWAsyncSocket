#if canImport(Network)
import Foundation
import Network

/// Error types specific to NWAsyncSocket.
public enum NWAsyncSocketError: Error, LocalizedError {
    case notConnected
    case alreadyConnected
    case connectionFailed(Error)
    case readTimeout
    case writeTimeout
    case invalidParameter(String)

    public var errorDescription: String? {
        switch self {
        case .notConnected: return "Socket is not connected."
        case .alreadyConnected: return "Socket is already connected."
        case .connectionFailed(let err): return "Connection failed: \(err.localizedDescription)"
        case .readTimeout: return "Read operation timed out."
        case .writeTimeout: return "Write operation timed out."
        case .invalidParameter(let msg): return "Invalid parameter: \(msg)"
        }
    }
}

/// A TCP socket built on top of `NWConnection` (Network.framework) with an API
/// modeled after GCDAsyncSocket. Includes built-in support for:
///
/// - **Sticky-packet / split-packet handling** via an internal `StreamBuffer`
/// - **SSE (Server-Sent Events) parsing** for LLM streaming data
/// - **UTF-8 boundary detection** to prevent character corruption
/// - **Read-request queue** for ordered, non-blocking reads
/// - **HTTP chunked transfer-encoding decoding** for proxied SSE streams
/// - **SSE auto-reconnect** with `Last-Event-ID` for seamless recovery
///
/// ## Thread safety
///
/// All socket I/O, buffer management and parsing run on a dedicated serial
/// `socketQueue` (a background `DispatchQueue` with `.userInitiated` QoS).
/// Delegate callbacks are dispatched to the caller-provided `delegateQueue`
/// (typically `DispatchQueue.main`).  This ensures that:
///
/// 1. The UI thread is never blocked by network operations.
/// 2. Parsing (SSE, chunked decoding) happens off the main thread,
///    reducing CPU and power usage.
/// 3. Delegate methods can safely update `@MainActor` / UI state when
///    `delegateQueue` is `.main`.
///
/// ## Quick Start
/// ```swift
/// let socket = NWAsyncSocket(delegate: self, delegateQueue: .main)
/// try socket.connect(toHost: "example.com", onPort: 8080)
/// socket.readData(withTimeout: -1, tag: 0)
/// ```
public final class NWAsyncSocket {

    // MARK: - Public properties

    /// The delegate that receives socket events.
    public weak var delegate: NWAsyncSocketDelegate?

    /// The dispatch queue on which delegate methods are called.
    public let delegateQueue: DispatchQueue

    /// Whether the socket is currently connected.
    public private(set) var isConnected: Bool = false

    /// The remote host the socket is connected to.
    public private(set) var connectedHost: String?

    /// The remote port the socket is connected to.
    public private(set) var connectedPort: UInt16 = 0

    /// User-defined data that can be attached to the socket instance.
    public var userData: Any?

    // MARK: - Internal state

    private var connection: NWConnection?
    /// Dedicated serial queue for all socket I/O and parsing.
    /// Ensures thread-safe access to `buffer`, `readQueue`, `sseParser`, etc.
    private let socketQueue: DispatchQueue
    private let buffer = StreamBuffer()
    private var readQueue: [ReadRequest] = []
    private var isReadingContinuously = false

    // SSE / streaming text mode
    private var sseParser: SSEParser?
    private var streamingTextEnabled = false

    // HTTP chunked transfer-encoding decoder
    private var chunkedDecoder: ChunkedDecoder?

    // TLS
    private var tlsEnabled = false

    // SSE auto-reconnect
    private var sseAutoReconnectEnabled = false
    private var sseRetryInterval: TimeInterval = 3.0
    private var lastConnectedHost: String?
    private var lastConnectedPort: UInt16 = 0
    private var reconnectWorkItem: DispatchWorkItem?

    // MARK: - Init

    /// Create a new socket.
    ///
    /// - Parameters:
    ///   - delegate: The delegate to receive callbacks.
    ///   - delegateQueue: The queue for delegate callbacks. Defaults to `.main`.
    public init(delegate: NWAsyncSocketDelegate? = nil,
                delegateQueue: DispatchQueue = .main) {
        self.delegate = delegate
        self.delegateQueue = delegateQueue
        self.socketQueue = DispatchQueue(label: "com.nwasyncsocket.socketQueue",
                                         qos: .userInitiated)
    }

    // MARK: - Configuration

    /// Enable TLS for the connection. Must be called before `connect(toHost:onPort:)`.
    public func enableTLS() {
        tlsEnabled = true
    }

    /// Enable SSE (Server-Sent Events) parsing mode.
    /// When enabled, incoming data is automatically fed through the SSE parser
    /// and complete events are delivered via `socket(_:didReceiveSSEEvent:)`.
    public func enableSSEParsing() {
        socketQueue.async { [weak self] in
            self?.sseParser = SSEParser()
        }
    }

    /// Enable streaming text mode.
    /// When enabled, incoming data is extracted as UTF-8 safe strings and
    /// delivered via `socket(_:didReceiveString:)`.
    public func enableStreamingText() {
        socketQueue.async { [weak self] in
            self?.streamingTextEnabled = true
        }
    }

    /// Enable HTTP chunked transfer-encoding decoding.
    ///
    /// When enabled, incoming data passes through a `ChunkedDecoder` before
    /// reaching the SSE parser or streaming text layer. This is required when
    /// the backend sits behind Nginx, a CDN, or any proxy that applies
    /// `Transfer-Encoding: chunked` to the response.
    public func enableChunkedDecoding() {
        socketQueue.async { [weak self] in
            self?.chunkedDecoder = ChunkedDecoder()
        }
    }

    /// Enable automatic reconnection for SSE streams.
    ///
    /// When enabled, the socket will automatically attempt to reconnect after
    /// an unexpected disconnection while SSE parsing is active. On reconnect
    /// the delegate receives `socket(_:willAutoReconnectWithLastEventId:afterDelay:)`
    /// so the application can include the `Last-Event-ID` HTTP header in the
    /// new request, allowing the server to resume from the last seen event.
    ///
    /// - Parameter retryInterval: Default delay in seconds before a reconnect
    ///   attempt. If the SSE stream sends a `retry:` field, that value takes
    ///   precedence. Defaults to `3.0` seconds.
    public func enableSSEAutoReconnect(retryInterval: TimeInterval = 3.0) {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            self.sseAutoReconnectEnabled = true
            self.sseRetryInterval = retryInterval
        }
    }

    // MARK: - Connect

    /// Connect to the specified host and port.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address.
    ///   - port: The TCP port number.
    /// - Throws: `NWAsyncSocketError.alreadyConnected` if already connected.
    public func connect(toHost host: String, onPort port: UInt16) throws {
        try connect(toHost: host, onPort: port, withTimeout: -1)
    }

    /// Connect to the specified host and port with a timeout.
    ///
    /// - Parameters:
    ///   - host: The hostname or IP address.
    ///   - port: The TCP port number.
    ///   - timeout: Connection timeout in seconds. Negative means no timeout.
    /// - Throws: `NWAsyncSocketError.alreadyConnected` if already connected.
    public func connect(toHost host: String, onPort port: UInt16, withTimeout timeout: TimeInterval) throws {
        guard !isConnected else { throw NWAsyncSocketError.alreadyConnected }

        let parameters: NWParameters
        if tlsEnabled {
            parameters = .tls
        } else {
            parameters = .tcp
        }

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)

        self.connection = conn
        self.connectedHost = host
        self.connectedPort = port
        // Remember for auto-reconnect.
        self.lastConnectedHost = host
        self.lastConnectedPort = port

        conn.stateUpdateHandler = { [weak self] state in
            self?.handleStateChange(state)
        }

        conn.start(queue: socketQueue)

        // Timeout
        if timeout > 0 {
            socketQueue.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self = self, !self.isConnected else { return }
                self.disconnect(withError: NWAsyncSocketError.connectionFailed(
                    NWAsyncSocketError.readTimeout))
            }
        }
    }

    // MARK: - Disconnect

    /// Disconnect the socket gracefully.
    public func disconnect() {
        socketQueue.async { [weak self] in
            self?.cancelAutoReconnect()
            self?.disconnectInternal(error: nil)
        }
    }

    /// Disconnect after all pending writes have completed.
    public func disconnectAfterWriting() {
        socketQueue.async { [weak self] in
            // For now, behave like disconnect. A more sophisticated implementation
            // could wait for the write queue to drain.
            self?.cancelAutoReconnect()
            self?.disconnectInternal(error: nil)
        }
    }

    /// Disconnect after all pending reads have completed.
    public func disconnectAfterReading() {
        socketQueue.async { [weak self] in
            self?.cancelAutoReconnect()
            self?.disconnectInternal(error: nil)
        }
    }

    // MARK: - Reading

    /// Enqueue a read for any available data.
    ///
    /// - Parameters:
    ///   - timeout: Read timeout in seconds. Negative means no timeout.
    ///   - tag: An application-defined tag for correlating callbacks.
    public func readData(withTimeout timeout: TimeInterval, tag: Int) {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            let request = ReadRequest(type: .available, timeout: timeout, tag: tag)
            self.readQueue.append(request)
            self.dequeueNextRead()
        }
    }

    /// Enqueue a read for exactly `length` bytes.
    ///
    /// - Parameters:
    ///   - length: The exact number of bytes to read.
    ///   - timeout: Read timeout in seconds. Negative means no timeout.
    ///   - tag: An application-defined tag for correlating callbacks.
    public func readData(toLength length: UInt, withTimeout timeout: TimeInterval, tag: Int) {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            let request = ReadRequest(type: .toLength(Int(length)), timeout: timeout, tag: tag)
            self.readQueue.append(request)
            self.dequeueNextRead()
        }
    }

    /// Enqueue a read that completes when the specified delimiter is found.
    ///
    /// - Parameters:
    ///   - data: The delimiter data to search for.
    ///   - timeout: Read timeout in seconds. Negative means no timeout.
    ///   - tag: An application-defined tag for correlating callbacks.
    public func readData(toData data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            let request = ReadRequest(type: .toDelimiter(data), timeout: timeout, tag: tag)
            self.readQueue.append(request)
            self.dequeueNextRead()
        }
    }

    // MARK: - Writing

    /// Write data to the socket.
    ///
    /// - Parameters:
    ///   - data: The data to write.
    ///   - timeout: Write timeout in seconds. Negative means no timeout.
    ///   - tag: An application-defined tag for correlating callbacks.
    public func write(_ data: Data, withTimeout timeout: TimeInterval, tag: Int) {
        socketQueue.async { [weak self] in
            guard let self = self else { return }
            guard let conn = self.connection, self.isConnected else {
                self.delegateQueue.async {
                    self.delegate?.socketDidDisconnect(self, withError: NWAsyncSocketError.notConnected)
                }
                return
            }

            var timedOut = false
            var writeCompleted = false
            var timeoutWorkItem: DispatchWorkItem?

            if timeout > 0 {
                let workItem = DispatchWorkItem { [weak self] in
                    guard let self = self, !writeCompleted else { return }
                    timedOut = true
                    self.disconnect(withError: NWAsyncSocketError.writeTimeout)
                }
                timeoutWorkItem = workItem
                self.socketQueue.asyncAfter(deadline: .now() + timeout, execute: workItem)
            }

            conn.send(content: data, completion: .contentProcessed { [weak self] error in
                writeCompleted = true
                timeoutWorkItem?.cancel()
                guard let self = self, !timedOut else { return }
                if let error = error {
                    self.disconnect(withError: error)
                } else {
                    self.delegateQueue.async {
                        self.delegate?.socket(self, didWriteDataWithTag: tag)
                    }
                }
            })
        }
    }

    // MARK: - Private: State handling

    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            isConnected = true
            let host = connectedHost ?? ""
            let port = connectedPort
            delegateQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.socket(self, didConnectToHost: host, port: port)
            }
            // Start the continuous read loop
            startContinuousRead()

        case .failed(let error):
            disconnectInternal(error: error)

        case .cancelled:
            disconnectInternal(error: nil)

        case .waiting(let error):
            // Connection is waiting (e.g. no network). Report but keep alive.
            _ = error

        default:
            break
        }
    }

    // MARK: - Private: Continuous read loop

    /// Start a continuous read loop that feeds incoming data into the buffer.
    /// This is the core of the streaming architecture – data is always being
    /// read from the connection and accumulated in the buffer, then dispatched
    /// to satisfy queued read requests.
    ///
    /// All processing runs on `socketQueue` (a background serial queue) to
    /// keep the main / UI thread free.
    private func startContinuousRead() {
        guard !isReadingContinuously else { return }
        isReadingContinuously = true
        readNextChunk()
    }

    private func readNextChunk() {
        guard let conn = connection, isConnected else { return }

        conn.receive(minimumIncompleteLength: 1,
                     maximumLength: 65536) { [weak self] content, _, isComplete, error in
            guard let self = self else { return }

            if let rawData = content, !rawData.isEmpty {
                // De-chunk if HTTP chunked encoding is active.
                let data: Data
                if let decoder = self.chunkedDecoder {
                    data = decoder.decode(rawData)
                } else {
                    data = rawData
                }

                if !data.isEmpty {
                    self.buffer.append(data)

                    // SSE parsing mode
                    if let parser = self.sseParser {
                        let events = parser.parse(data)
                        for event in events {
                            // Update retry interval if the server sent one.
                            if let retry = event.retry {
                                self.sseRetryInterval = TimeInterval(retry) / 1000.0
                            }
                            self.delegateQueue.async {
                                self.delegate?.socket(self, didReceiveSSEEvent: event)
                            }
                        }
                    }

                    // Streaming text mode: extract UTF-8 safe string from the
                    // newly received data without consuming the buffer, so
                    // queued reads can still access the raw bytes.
                    if self.streamingTextEnabled {
                        let safeCount = StreamBuffer.utf8SafeByteCount(data)
                        if safeCount > 0, let str = String(data: data.prefix(safeCount), encoding: .utf8) {
                            self.delegateQueue.async {
                                self.delegate?.socket(self, didReceiveString: str)
                            }
                        }
                    }

                    // Try to satisfy queued read requests
                    self.processReadQueue()
                }
            }

            if isComplete {
                self.disconnectInternal(error: nil)
                return
            }

            if let error = error {
                self.disconnectInternal(error: error)
                return
            }

            // Continue reading
            self.readNextChunk()
        }
    }

    // MARK: - Private: Read queue processing

    private func dequeueNextRead() {
        // Try to satisfy from existing buffer first
        processReadQueue()
    }

    private func processReadQueue() {
        while !readQueue.isEmpty {
            let request = readQueue[0]

            switch request.type {
            case .available:
                if !buffer.isEmpty {
                    let data = buffer.readAllData()
                    readQueue.removeFirst()
                    let tag = request.tag
                    delegateQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.socket(self, didRead: data, withTag: tag)
                    }
                } else {
                    // No data available yet; wait for more.
                    return
                }

            case .toLength(let length):
                if let data = buffer.readData(toLength: length) {
                    readQueue.removeFirst()
                    let tag = request.tag
                    delegateQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.socket(self, didRead: data, withTag: tag)
                    }
                } else {
                    // Not enough bytes yet; wait for more.
                    return
                }

            case .toDelimiter(let delimiter):
                if let data = buffer.readData(toDelimiter: delimiter) {
                    readQueue.removeFirst()
                    let tag = request.tag
                    delegateQueue.async { [weak self] in
                        guard let self = self else { return }
                        self.delegate?.socket(self, didRead: data, withTag: tag)
                    }
                } else {
                    // Delimiter not found yet; wait for more.
                    return
                }
            }
        }
    }

    // MARK: - Private: Auto-reconnect

    private func scheduleAutoReconnect() {
        guard sseAutoReconnectEnabled,
              sseParser != nil,
              let host = lastConnectedHost else { return }
        let port = lastConnectedPort
        let lastId = sseParser?.lastEventId
        let delay = sseRetryInterval

        // Notify delegate about the upcoming reconnection.
        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.socket(self, willAutoReconnectWithLastEventId: lastId, afterDelay: delay)
        }

        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            // Reset transient state but keep the parser (preserves lastEventId).
            self.chunkedDecoder?.reset()
            do {
                try self.connect(toHost: host, onPort: port)
            } catch {
                self.delegateQueue.async {
                    self.delegate?.socketDidDisconnect(self, withError: error)
                }
            }
        }
        reconnectWorkItem = workItem
        socketQueue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }

    private func cancelAutoReconnect() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        sseAutoReconnectEnabled = false
    }

    // MARK: - Private: Disconnect

    private func disconnect(withError error: Error?) {
        socketQueue.async { [weak self] in
            self?.disconnectInternal(error: error)
        }
    }

    private func disconnectInternal(error: Error?) {
        guard isConnected || connection != nil else { return }

        let shouldAutoReconnect = sseAutoReconnectEnabled && sseParser != nil && error != nil

        isConnected = false
        isReadingContinuously = false
        connection?.cancel()
        connection = nil
        connectedHost = nil
        connectedPort = 0
        readQueue.removeAll()
        buffer.reset()
        // Note: sseParser is intentionally NOT reset here so that
        // lastEventId survives across reconnections.

        if shouldAutoReconnect {
            scheduleAutoReconnect()
        } else {
            sseParser?.reset()
            delegateQueue.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.socketDidDisconnect(self, withError: error)
            }
        }
    }
}

#endif // canImport(Network)
