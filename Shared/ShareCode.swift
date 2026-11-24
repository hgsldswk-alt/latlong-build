import Foundation

struct ShareCode: Codable, Equatable, Sendable {
    let coordinate: Coordinate
    let name: String?
    let accuracy: Double?
    let quality: Quality?

    var isValid: Bool {
        coordinate.isValid &&
        (name.map { $0.count <= 80 && $0.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) } } ?? true) &&
        (accuracy.map { $0.isFinite && $0 >= 0 } ?? true) &&
        (quality == nil || accuracy != nil)
    }

    static let maxBytes = 1024

    func encode() throws -> String {
        guard isValid else { throw CodeError.invalid }
        let data = try JSONEncoder().encode(self)
        let text = "LL1:" + data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        guard text.utf8.count <= Self.maxBytes else { throw CodeError.invalid }
        return text
    }

    static func decode(_ text: String) throws -> ShareCode {
        guard text.utf8.count <= maxBytes else { throw CodeError.invalid }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("LL1:") else { throw CodeError.invalid }
        let body = trimmed.dropFirst(4)
        guard !body.isEmpty, body.utf8.allSatisfy({ byte in
            (48...57).contains(byte) || (65...90).contains(byte) || (97...122).contains(byte) || byte == 45 || byte == 95
        }) else { throw CodeError.invalid }
        var base64 = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        guard let data = Data(base64Encoded: base64),
              let fields = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              Set(fields.keys).isSubset(of: ["coordinate", "name", "accuracy", "quality"]),
              let coordinate = fields["coordinate"] as? [String: Any],
              Set(coordinate.keys) == ["latitude", "longitude"],
              let payload = try? JSONDecoder().decode(Self.self, from: data), payload.isValid else {
            throw CodeError.invalid
        }
        return payload
    }

    static func readFile(_ url: URL) throws -> String {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let data = try handle.read(upToCount: maxBytes + 1) ?? Data()
        guard data.count <= maxBytes, let text = String(data: data, encoding: .utf8) else { throw CodeError.invalid }
        return text
    }
}

enum CodeError: Error { case invalid }
