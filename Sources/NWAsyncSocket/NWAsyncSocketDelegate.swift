#if canImport(Network)
import Foundation

/// Delegate protocol for `NWAsyncSocket`, modeled after `GCDAsyncSocketDelegate`.
///
/// All delegate methods are called on the queue specified during initialization
/// (the `delegateQueue`), ensuring that UI updates happen on the main thread
/// when `.main` is used as the delegate queue.
public protocol NWAsyncSocketDelegate: AnyObject {

    /// Called when the socket successfully connects to the remote host.
    func socket(_ sock: NWAsyncSocket, didConnectToHost host: String, port: UInt16)

    /// Called when data has been read from the socket in response to a
    /// `readData(withTimeout:tag:)` call.
    func socket(_ sock: NWAsyncSocket, didRead data: Data, withTag tag: Int)

    /// Called after data has been successfully written in response to a
    /// `write(_:withTimeout:tag:)` call.
    func socket(_ sock: NWAsyncSocket, didWriteDataWithTag tag: Int)

    /// Called when the socket disconnects, optionally with an error.
    func socketDidDisconnect(_ sock: NWAsyncSocket, withError error: Error?)

    // MARK: - Optional SSE callbacks

    /// Called when a complete SSE event has been parsed from the stream.
    /// Only invoked when SSE parsing mode is enabled via `enableSSEParsing()`.
    func socket(_ sock: NWAsyncSocket, didReceiveSSEEvent event: SSEEvent)

    /// Called when a UTF-8 safe string chunk has been extracted from the stream.
    /// Only invoked when streaming text mode is enabled via `enableStreamingText()`.
    func socket(_ sock: NWAsyncSocket, didReceiveString string: String)

    // MARK: - Optional reconnection callbacks

    /// Called when the socket is about to auto-reconnect after an SSE
    /// disconnection.  The `lastEventId` (if available) should be included
    /// in the subsequent HTTP request's `Last-Event-ID` header so the
    /// server can resume from where the client left off.
    ///
    /// Only invoked when SSE auto-reconnect is enabled via
    /// `enableSSEAutoReconnect(retryInterval:)`.
    ///
    /// - Parameters:
    ///   - sock: The socket instance.
    ///   - lastEventId: The most recent `id` field received before the
    ///     disconnect, or `nil` if no id was seen.
    ///   - retryInterval: Seconds until the reconnection attempt.
    func socket(_ sock: NWAsyncSocket, willAutoReconnectWithLastEventId lastEventId: String?, afterDelay retryInterval: TimeInterval)
}

// MARK: - Default implementations (optional methods)

public extension NWAsyncSocketDelegate {
    func socket(_ sock: NWAsyncSocket, didReceiveSSEEvent event: SSEEvent) {}
    func socket(_ sock: NWAsyncSocket, didReceiveString string: String) {}
    func socket(_ sock: NWAsyncSocket, willAutoReconnectWithLastEventId lastEventId: String?, afterDelay retryInterval: TimeInterval) {}
}

#endif // canImport(Network)
