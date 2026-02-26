import Foundation

/// The type of a read operation enqueued on the socket.
public enum ReadRequestType: Sendable {
    /// Read any available data (up to a maximum if specified).
    case available
    /// Read exactly `length` bytes.
    case toLength(Int)
    /// Read until `delimiter` is found in the stream.
    case toDelimiter(Data)
}

/// Represents a pending read operation in the read-request queue.
/// Modeled after GCDAsyncSocket's internal read mechanism.
public struct ReadRequest: Sendable {
    /// The type of read to perform.
    public let type: ReadRequestType
    /// Timeout in seconds. Negative means no timeout.
    public let timeout: TimeInterval
    /// An application-defined tag for correlating delegate callbacks.
    public let tag: Int

    public init(type: ReadRequestType, timeout: TimeInterval, tag: Int) {
        self.type = type
        self.timeout = timeout
        self.tag = tag
    }
}
