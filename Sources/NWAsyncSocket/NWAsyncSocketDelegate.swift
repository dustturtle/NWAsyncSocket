#if canImport(Network)
import Foundation

/// Delegate protocol for `NWAsyncSocket`, modeled after `GCDAsyncSocketDelegate`.
///
/// All delegate methods are called on the queue specified during initialization.
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
}

// MARK: - Default implementations (optional methods)

public extension NWAsyncSocketDelegate {
    func socket(_ sock: NWAsyncSocket, didReceiveSSEEvent event: SSEEvent) {}
    func socket(_ sock: NWAsyncSocket, didReceiveString string: String) {}
}

#endif // canImport(Network)
