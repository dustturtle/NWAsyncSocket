import Foundation

/// A byte buffer that accumulates incoming TCP data and supports extracting
/// complete messages from the stream. Handles sticky-packet (粘包) reassembly,
/// split-packet reconstruction, and UTF-8 boundary detection.
public final class StreamBuffer {

    // MARK: - Properties

    private var storage: Data

    /// Number of bytes currently in the buffer.
    public var count: Int { storage.count }

    /// Whether the buffer is empty.
    public var isEmpty: Bool { storage.isEmpty }

    /// A copy of the buffered data (for inspection / testing).
    public var data: Data { storage }

    // MARK: - Init

    public init() {
        storage = Data()
    }

    // MARK: - Append

    /// Append raw bytes received from the network.
    public func append(_ data: Data) {
        storage.append(data)
    }

    // MARK: - Read helpers

    /// Read and remove exactly `length` bytes from the front of the buffer.
    /// Returns `nil` if fewer bytes are available.
    public func readData(toLength length: Int) -> Data? {
        guard storage.count >= length else { return nil }
        let chunk = storage.prefix(length)
        storage.removeFirst(length)
        return Data(chunk)
    }

    /// Read and remove all bytes up to and including the first occurrence of
    /// `delimiter`. Returns `nil` if the delimiter is not found.
    public func readData(toDelimiter delimiter: Data) -> Data? {
        guard let range = storage.range(of: delimiter) else { return nil }
        let chunk = Data(storage[storage.startIndex..<range.upperBound])
        storage = Data(storage[range.upperBound...])
        return chunk
    }

    /// Drain and return all available bytes.
    public func readAllData() -> Data {
        let result = storage
        storage = Data()
        return result
    }

    /// Peek at all data without consuming.
    public func peekAllData() -> Data {
        return storage
    }

    // MARK: - UTF-8 safe extraction

    /// Return the longest prefix of the buffer that forms valid UTF-8,
    /// leaving any trailing incomplete multi-byte sequence in the buffer.
    /// This prevents splitting a multi-byte character across two reads.
    public func readUTF8SafeString() -> String? {
        guard !storage.isEmpty else { return nil }
        let safeCount = StreamBuffer.utf8SafeByteCount(storage)
        guard safeCount > 0 else { return nil }
        guard let chunk = readData(toLength: safeCount) else { return nil }
        return String(data: chunk, encoding: .utf8)
    }

    // MARK: - Reset

    /// Discard all buffered data.
    public func reset() {
        storage = Data()
    }

    // MARK: - UTF-8 helpers

    /// Returns the number of leading bytes in `data` that form complete
    /// UTF-8 code points. Any trailing incomplete sequence is excluded.
    public static func utf8SafeByteCount(_ data: Data) -> Int {
        let bytes = Array(data)
        let total = bytes.count
        guard total > 0 else { return 0 }

        // Walk backwards from the end to find the start of any trailing
        // incomplete multi-byte sequence.
        var i = total - 1

        // Skip continuation bytes (10xxxxxx)
        while i >= 0 && (bytes[i] & 0xC0) == 0x80 {
            i -= 1
        }

        if i < 0 {
            // All continuation bytes with no leading byte – nothing is safe.
            return 0
        }

        let leadByte = bytes[i]
        let expectedLength: Int
        if leadByte & 0x80 == 0 {
            expectedLength = 1
        } else if leadByte & 0xE0 == 0xC0 {
            expectedLength = 2
        } else if leadByte & 0xF0 == 0xE0 {
            expectedLength = 3
        } else if leadByte & 0xF8 == 0xF0 {
            expectedLength = 4
        } else {
            // Invalid leading byte – treat everything up to it as safe
            // (the invalid byte will surface as a replacement character later).
            return total
        }

        let actualLength = total - i
        if actualLength >= expectedLength {
            // The last character is complete.
            return total
        } else {
            // The last character is incomplete – exclude it.
            return i
        }
    }
}
