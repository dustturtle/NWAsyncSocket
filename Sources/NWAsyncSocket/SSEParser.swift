import Foundation

/// Represents a single Server-Sent Events (SSE) event parsed from a stream.
public struct SSEEvent: Equatable, Sendable {
    /// The event type (from the `event:` field). Defaults to `"message"`.
    public let event: String
    /// The data payload (from `data:` fields, joined by newlines).
    public let data: String
    /// The optional `id:` field.
    public let id: String?
    /// The optional `retry:` field (milliseconds).
    public let retry: Int?

    public init(event: String = "message", data: String, id: String? = nil, retry: Int? = nil) {
        self.event = event
        self.data = data
        self.id = id
        self.retry = retry
    }
}

/// Incremental SSE parser that accumulates raw bytes and emits complete
/// `SSEEvent` values. Handles partial lines that arrive split across
/// multiple TCP segments.
///
/// **Performance**: Incoming data is accumulated as raw `Data` bytes.
/// Line-ending detection (`\r\n`, `\r`, `\n`) is performed at the byte
/// level, and `String` conversion is deferred until a complete event
/// boundary (`\n\n`) is reached. This minimises ARC traffic and CPU
/// usage on iOS compared to converting every incoming chunk to `String`.
///
/// SSE specification reference: https://html.spec.whatwg.org/multipage/server-sent-events.html
public final class SSEParser {

    // MARK: - Properties

    /// Accumulated raw bytes that have not yet formed a complete line.
    /// Kept as `Data` to avoid repeated String allocations; conversion to
    /// `String` is deferred until a complete event is dispatched.
    private var lineBuffer = Data()

    // Fields being built for the current event (stored as raw bytes
    // until the event boundary triggers String conversion).
    private var currentEvent: String = "message"
    private var currentDataParts: [Data] = []
    private var currentId: String?
    private var currentRetry: Int?

    /// Last seen event id (for reconnection with `Last-Event-ID`).
    public private(set) var lastEventId: String?

    // MARK: - ASCII byte constants

    private static let LF: UInt8    = 0x0A  // \n
    private static let CR: UInt8    = 0x0D  // \r
    private static let COLON: UInt8 = 0x3A  // :
    private static let SPACE: UInt8 = 0x20  // ' '
    private static let NUL: UInt8   = 0x00  // \0

    // Pre-computed field name bytes for fast comparison.
    private static let fieldEvent = Array("event".utf8)
    private static let fieldData  = Array("data".utf8)
    private static let fieldId    = Array("id".utf8)
    private static let fieldRetry = Array("retry".utf8)

    // MARK: - Init

    public init() {}

    // MARK: - Feed data

    /// Feed raw bytes into the parser. Returns an array of fully parsed events.
    /// Partial lines are buffered internally until a newline arrives.
    ///
    /// Data is accumulated in byte form; `String` conversion is deferred
    /// until a complete event boundary (`\n\n`) is reached, reducing
    /// CPU and ARC overhead on iOS.
    public func parse(_ data: Data) -> [SSEEvent] {
        guard !data.isEmpty else { return [] }
        var events: [SSEEvent] = []
        lineBuffer.append(data)

        // Process all complete lines at the byte level.
        var scanOffset = 0
        while scanOffset < lineBuffer.count {
            guard let (lineData, afterLineOffset) = extractLineBytes(from: scanOffset) else {
                break
            }
            processLineBytes(lineData, events: &events)
            scanOffset = afterLineOffset
        }

        // Remove consumed bytes.
        if scanOffset > 0 {
            if scanOffset >= lineBuffer.count {
                lineBuffer = Data()
            } else {
                lineBuffer = Data(lineBuffer.suffix(from: lineBuffer.startIndex + scanOffset))
            }
        }

        return events
    }

    /// Feed a string chunk into the parser.
    public func parse(_ text: String) -> [SSEEvent] {
        guard let data = text.data(using: .utf8) else { return [] }
        return parse(data)
    }

    /// Reset all internal state.
    public func reset() {
        lineBuffer = Data()
        resetCurrentEvent()
    }

    // MARK: - Private: Byte-level line extraction

    /// Extract the first complete line from `lineBuffer` starting at `offset`.
    /// Scans for `\r\n`, `\r`, or `\n` terminators at the byte level.
    /// Returns `(lineData, offsetAfterLineEnding)` or `nil` if no complete
    /// line exists yet.
    private func extractLineBytes(from offset: Int) -> (Data, Int)? {
        let start = lineBuffer.startIndex + offset
        var i = offset
        while i < lineBuffer.count {
            let byte = lineBuffer[lineBuffer.startIndex + i]
            if byte == SSEParser.CR {
                let lineData = Data(lineBuffer[start..<(lineBuffer.startIndex + i)])
                // \r\n counts as a single line ending
                if i + 1 < lineBuffer.count && lineBuffer[lineBuffer.startIndex + i + 1] == SSEParser.LF {
                    return (lineData, i + 2)
                } else {
                    return (lineData, i + 1)
                }
            } else if byte == SSEParser.LF {
                let lineData = Data(lineBuffer[start..<(lineBuffer.startIndex + i)])
                return (lineData, i + 1)
            }
            i += 1
        }
        return nil
    }

    /// Process a single complete line (as raw bytes) according to SSE rules.
    /// String conversion is deferred; field names are compared as raw bytes.
    private func processLineBytes(_ lineData: Data, events: inout [SSEEvent]) {
        // Empty line = dispatch the event.
        if lineData.isEmpty {
            dispatchEvent(into: &events)
            return
        }

        // Lines starting with ':' are comments – ignore.
        if lineData[lineData.startIndex] == SSEParser.COLON {
            return
        }

        // Split on first ':' at the byte level.
        let fieldBytes: Data
        let valueBytes: Data
        if let colonPos = lineData.firstIndex(of: SSEParser.COLON) {
            fieldBytes = Data(lineData[lineData.startIndex..<colonPos])
            var valStart = lineData.index(after: colonPos)
            // Skip a single leading space after the colon (per spec).
            if valStart < lineData.endIndex && lineData[valStart] == SSEParser.SPACE {
                valStart = lineData.index(after: valStart)
            }
            valueBytes = Data(lineData[valStart..<lineData.endIndex])
        } else {
            fieldBytes = lineData
            valueBytes = Data()
        }

        // Compare field names as raw bytes for performance.
        if fieldBytes.elementsEqual(SSEParser.fieldEvent) {
            currentEvent = String(data: valueBytes, encoding: .utf8) ?? "message"
        } else if fieldBytes.elementsEqual(SSEParser.fieldData) {
            currentDataParts.append(valueBytes)
        } else if fieldBytes.elementsEqual(SSEParser.fieldId) {
            // Per spec, ignore if value contains null byte.
            if !valueBytes.contains(SSEParser.NUL) {
                currentId = String(data: valueBytes, encoding: .utf8)
            }
        } else if fieldBytes.elementsEqual(SSEParser.fieldRetry) {
            if let str = String(data: valueBytes, encoding: .utf8), let ms = Int(str) {
                currentRetry = ms
            }
        }
        // Unknown field – ignore per spec.
    }

    private func dispatchEvent(into events: inout [SSEEvent]) {
        // Only dispatch if we have at least one data field.
        if !currentDataParts.isEmpty {
            // Join data parts with \n, performing a single String conversion.
            let joinedData: Data
            if currentDataParts.count == 1 {
                joinedData = currentDataParts[0]
            } else {
                var combined = Data()
                for (i, part) in currentDataParts.enumerated() {
                    if i > 0 {
                        combined.append(SSEParser.LF)
                    }
                    combined.append(part)
                }
                joinedData = combined
            }
            let dataStr = String(data: joinedData, encoding: .utf8) ?? ""
            let event = SSEEvent(
                event: currentEvent,
                data: dataStr,
                id: currentId,
                retry: currentRetry
            )
            events.append(event)
            // Update last event id.
            if let id = currentId {
                lastEventId = id
            }
        }
        resetCurrentEvent()
    }

    private func resetCurrentEvent() {
        currentEvent = "message"
        currentDataParts = []
        currentId = nil
        currentRetry = nil
    }
}
