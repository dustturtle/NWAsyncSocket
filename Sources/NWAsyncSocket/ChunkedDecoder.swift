import Foundation

/// Incremental decoder for HTTP `Transfer-Encoding: chunked` byte streams.
///
/// When the backend sits behind Nginx, a CDN, or any proxy that applies
/// chunked transfer-encoding, the raw bytes received on the socket are not
/// plain SSE lines but instead follow the HTTP chunked format:
///
/// ```
/// <hex-size>\r\n
/// <data>\r\n
/// ...
/// 0\r\n
/// \r\n
/// ```
///
/// `ChunkedDecoder` strips the framing and yields clean data that can be
/// fed directly into an `SSEParser` or any other stream consumer.
///
/// The decoder is fully incremental: it handles partial chunks that arrive
/// split across multiple TCP segments.
public final class ChunkedDecoder {

    // MARK: - State machine

    private enum State {
        /// Waiting for the hex-length line terminated by `\r\n`.
        case waitingForSize
        /// Reading `remaining` bytes of chunk data.
        case readingData(remaining: Int)
        /// Expecting the `\r\n` trailer after a chunk's data.
        case readingTrailer
        /// The final `0\r\n\r\n` chunk has been received.
        case complete
    }

    // MARK: - Properties

    private var state: State = .waitingForSize
    private var buffer = Data()

    /// Whether the final zero-length chunk has been received.
    public var isComplete: Bool {
        if case .complete = state { return true }
        return false
    }

    // MARK: - Init

    public init() {}

    // MARK: - Decode

    /// Feed raw bytes from the socket and return decoded (de-chunked) data.
    ///
    /// Any leftover bytes that do not yet form a complete chunk component
    /// are buffered internally until the next call.
    public func decode(_ data: Data) -> Data {
        buffer.append(data)
        var output = Data()

        loop: while !buffer.isEmpty {
            switch state {
            case .waitingForSize:
                // Look for the CRLF that terminates the size line.
                guard let crlfRange = buffer.range(of: Data([0x0D, 0x0A])) else {
                    break loop  // Need more data.
                }
                let sizeLine = Data(buffer[buffer.startIndex..<crlfRange.lowerBound])
                buffer = Data(buffer[crlfRange.upperBound...])

                // Parse hex size. Extensions after ';' are allowed by the spec.
                guard let sizeStr = String(data: sizeLine, encoding: .ascii) else {
                    break loop
                }
                let hexPart = sizeStr.split(separator: ";").first.map(String.init) ?? sizeStr
                guard let chunkSize = Int(hexPart.trimmingCharacters(in: .whitespaces), radix: 16) else {
                    break loop
                }

                if chunkSize == 0 {
                    state = .complete
                    break loop
                }
                state = .readingData(remaining: chunkSize)

            case .readingData(let remaining):
                let available = min(remaining, buffer.count)
                output.append(buffer.prefix(available))
                buffer = Data(buffer.suffix(from: buffer.startIndex + available))
                let newRemaining = remaining - available
                if newRemaining > 0 {
                    state = .readingData(remaining: newRemaining)
                    break loop  // Need more data.
                }
                state = .readingTrailer

            case .readingTrailer:
                // Each chunk's data is followed by a `\r\n`.
                if buffer.count < 2 {
                    break loop  // Need more data.
                }
                // Skip the trailing CRLF.
                if buffer[buffer.startIndex] == 0x0D
                    && buffer[buffer.index(after: buffer.startIndex)] == 0x0A {
                    buffer = Data(buffer.suffix(from: buffer.startIndex + 2))
                }
                state = .waitingForSize

            case .complete:
                break loop
            }
        }

        return output
    }

    // MARK: - Reset

    /// Discard all internal state and prepare for a new chunked stream.
    public func reset() {
        state = .waitingForSize
        buffer = Data()
    }
}
