import Foundation

struct SSEEvent {
    let name: String?
    let data: Data
}

enum SSEClient {
    typealias HTTPErrorFactory = (_ response: HTTPURLResponse, _ data: Data) -> Error

    static func events(
        for request: URLRequest,
        httpError: @escaping HTTPErrorFactory
    ) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    guard let http = response as? HTTPURLResponse else {
                        throw LLMAPIError(message: "Serwer zwrócił nieprawidłową odpowiedź.")
                    }

                    guard (200..<300).contains(http.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        throw httpError(http, errorData)
                    }

                    var lineDecoder = SSELineDecoder()
                    var parser = SSEParser()
                    for try await byte in bytes {
                        try Task.checkCancellation()
                        if let line = lineDecoder.consume(byte),
                           let event = parser.consume(line) {
                            continuation.yield(event)
                        }
                    }
                    if let line = lineDecoder.finish(),
                       let event = parser.consume(line) {
                        continuation.yield(event)
                    }
                    if let event = parser.finish() {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}

struct SSELineDecoder {
    private var buffer = Data()
    private var previousByteWasCR = false

    mutating func consume(_ byte: UInt8) -> String? {
        switch byte {
        case 0x0A: // LF
            if previousByteWasCR {
                previousByteWasCR = false
                return nil
            }
            return emitLine()
        case 0x0D: // CR
            previousByteWasCR = true
            return emitLine()
        default:
            previousByteWasCR = false
            buffer.append(byte)
            return nil
        }
    }

    mutating func finish() -> String? {
        guard !buffer.isEmpty else { return nil }
        return emitLine()
    }

    private mutating func emitLine() -> String {
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }
}

struct SSEParser {
    private var eventName: String?
    private var dataLines: [String] = []

    mutating func consume(_ line: String) -> SSEEvent? {
        guard !line.isEmpty else { return flush() }
        guard !line.hasPrefix(":") else { return nil }

        if line.hasPrefix("event:") {
            eventName = fieldValue(in: line, after: "event:")
        } else if line.hasPrefix("data:") {
            dataLines.append(fieldValue(in: line, after: "data:"))
        }
        return nil
    }

    mutating func finish() -> SSEEvent? {
        flush()
    }

    private func fieldValue(in line: String, after prefix: String) -> String {
        var value = String(line.dropFirst(prefix.count))
        if value.first == " " {
            value.removeFirst()
        }
        return value
    }

    private mutating func flush() -> SSEEvent? {
        defer {
            eventName = nil
            dataLines.removeAll(keepingCapacity: true)
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(
            name: eventName,
            data: Data(dataLines.joined(separator: "\n").utf8)
        )
    }
}
