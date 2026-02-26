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
/// SSE specification reference: https://html.spec.whatwg.org/multipage/server-sent-events.html
public final class SSEParser {

    // MARK: - Properties

    /// Accumulated raw bytes that have not yet formed a complete line.
    private var lineBuffer: String = ""

    // Fields being built for the current event
    private var currentEvent: String = "message"
    private var currentData: [String] = []
    private var currentId: String?
    private var currentRetry: Int?

    /// Last seen event id (for reconnection).
    public private(set) var lastEventId: String?

    // MARK: - Init

    public init() {}

    // MARK: - Feed data

    /// Feed raw bytes into the parser. Returns an array of fully parsed events.
    /// Partial lines are buffered internally until a newline arrives.
    public func parse(_ data: Data) -> [SSEEvent] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return parse(text)
    }

    /// Feed a string chunk into the parser.
    public func parse(_ text: String) -> [SSEEvent] {
        var events: [SSEEvent] = []
        lineBuffer.append(text)

        // Process all complete lines (terminated by \r\n, \r, or \n).
        while let (line, remainder) = extractLine(from: lineBuffer) {
            lineBuffer = remainder
            processLine(line, events: &events)
        }

        return events
    }

    /// Reset all internal state.
    public func reset() {
        lineBuffer = ""
        resetCurrentEvent()
    }

    // MARK: - Private

    /// Extract the first complete line from `buffer`.
    /// Returns `(line, remainder)` or `nil` if no complete line exists.
    ///
    /// Uses `UnicodeScalarView` to correctly handle `\r\n` which Swift's
    /// `Character` type treats as a single extended grapheme cluster.
    private func extractLine(from buffer: String) -> (String, String)? {
        let scalars = buffer.unicodeScalars
        var idx = scalars.startIndex
        while idx < scalars.endIndex {
            let scalar = scalars[idx]
            if scalar == "\r" {
                let lineEnd = idx
                let next = scalars.index(after: idx)
                // \r\n counts as a single line ending
                if next < scalars.endIndex && scalars[next] == "\n" {
                    let afterCRLF = scalars.index(after: next)
                    return (String(scalars[scalars.startIndex..<lineEnd]),
                            String(scalars[afterCRLF...]))
                } else {
                    return (String(scalars[scalars.startIndex..<lineEnd]),
                            String(scalars[next...]))
                }
            } else if scalar == "\n" {
                let lineEnd = idx
                let next = scalars.index(after: idx)
                return (String(scalars[scalars.startIndex..<lineEnd]),
                        String(scalars[next...]))
            }
            idx = scalars.index(after: idx)
        }
        return nil
    }

    /// Process a single complete line according to SSE rules.
    private func processLine(_ line: String, events: inout [SSEEvent]) {
        // Empty line = dispatch the event
        if line.isEmpty {
            dispatchEvent(into: &events)
            return
        }

        // Lines starting with ':' are comments – ignore.
        if line.hasPrefix(":") {
            return
        }

        // Split on first ':'
        let field: String
        let value: String
        if let colonIdx = line.firstIndex(of: ":") {
            field = String(line[line.startIndex..<colonIdx])
            var valStart = line.index(after: colonIdx)
            // Skip a single leading space after the colon (per spec).
            if valStart < line.endIndex && line[valStart] == " " {
                valStart = line.index(after: valStart)
            }
            value = String(line[valStart...])
        } else {
            field = line
            value = ""
        }

        switch field {
        case "event":
            currentEvent = value
        case "data":
            currentData.append(value)
        case "id":
            // Per spec, ignore if value contains null.
            if !value.contains("\0") {
                currentId = value
            }
        case "retry":
            if let ms = Int(value) {
                currentRetry = ms
            }
        default:
            // Unknown field – ignore per spec.
            break
        }
    }

    private func dispatchEvent(into events: inout [SSEEvent]) {
        // Only dispatch if we have at least one data field.
        if !currentData.isEmpty {
            let dataStr = currentData.joined(separator: "\n")
            let event = SSEEvent(
                event: currentEvent,
                data: dataStr,
                id: currentId,
                retry: currentRetry
            )
            events.append(event)
            // Update last event id
            if let id = currentId {
                lastEventId = id
            }
        }
        resetCurrentEvent()
    }

    private func resetCurrentEvent() {
        currentEvent = "message"
        currentData = []
        currentId = nil
        currentRetry = nil
    }
}
