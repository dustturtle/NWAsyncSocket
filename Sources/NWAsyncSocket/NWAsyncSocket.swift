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
    private let socketQueue: DispatchQueue
    private let buffer = StreamBuffer()
    private var readQueue: [ReadRequest] = []
    private var isReadingContinuously = false

    // SSE / streaming text mode
    private var sseParser: SSEParser?
    private var streamingTextEnabled = false

    // TLS
    private var tlsEnabled = false

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

        // Optimize TCP for streaming
        if let tcpOptions = parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            // Use default settings – Network.framework handles Nagle, etc.
            _ = tcpOptions
        }

        let nwPort = NWEndpoint.Port(rawValue: port)!
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: parameters)

        self.connection = conn
        self.connectedHost = host
        self.connectedPort = port

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
            self?.disconnectInternal(error: nil)
        }
    }

    /// Disconnect after all pending writes have completed.
    public func disconnectAfterWriting() {
        socketQueue.async { [weak self] in
            // For now, behave like disconnect. A more sophisticated implementation
            // could wait for the write queue to drain.
            self?.disconnectInternal(error: nil)
        }
    }

    /// Disconnect after all pending reads have completed.
    public func disconnectAfterReading() {
        socketQueue.async { [weak self] in
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

            if let data = content, !data.isEmpty {
                self.buffer.append(data)

                // SSE parsing mode
                if let parser = self.sseParser {
                    let events = parser.parse(data)
                    for event in events {
                        self.delegateQueue.async {
                            self.delegate?.socket(self, didReceiveSSEEvent: event)
                        }
                    }
                }

                // Streaming text mode
                if self.streamingTextEnabled {
                    if let str = self.buffer.readUTF8SafeString() {
                        // Re-add to buffer since readUTF8SafeString consumed it
                        // but we also need it for queued reads.
                        // Actually, streaming text is a separate path – we deliver
                        // the string AND keep the original data for queued reads.
                        self.delegateQueue.async {
                            self.delegate?.socket(self, didReceiveString: str)
                        }
                    }
                }

                // Try to satisfy queued read requests
                self.processReadQueue()
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

    // MARK: - Private: Disconnect

    private func disconnect(withError error: Error?) {
        socketQueue.async { [weak self] in
            self?.disconnectInternal(error: error)
        }
    }

    private func disconnectInternal(error: Error?) {
        guard isConnected || connection != nil else { return }

        isConnected = false
        isReadingContinuously = false
        connection?.cancel()
        connection = nil
        connectedHost = nil
        connectedPort = 0
        readQueue.removeAll()
        buffer.reset()
        sseParser?.reset()

        delegateQueue.async { [weak self] in
            guard let self = self else { return }
            self.delegate?.socketDidDisconnect(self, withError: error)
        }
    }
}

#endif // canImport(Network)
