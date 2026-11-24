import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Sendable {
    case csv, gpx, kml
    var id: String { rawValue }
}

struct ExportSnapshot: Sendable {
    let project: String
    let points: [Waypoint]

    func data(for format: ExportFormat) -> Data {
        let date = ISO8601DateFormatter()
        date.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        date.timeZone = TimeZone(secondsFromGMT: 0)
        let ordered = points.sorted { $0.seq < $1.seq }
        switch format {
        case .csv:
            var rows = ["seq,project,latitude,longitude,horizontal_accuracy_m,fix_time_utc,saved_time_utc,name,source,quality"]
            for point in ordered {
                rows.append([
                    String(point.seq), Self.csv(project), Self.measure(point.coordinate.latitude),
                    Self.measure(point.coordinate.longitude), point.accuracy.map(Self.measure) ?? "",
                    point.fixTime.map(date.string(from:)) ?? "", date.string(from: point.savedTime),
                    Self.csv(point.displayName), point.source.rawValue, point.quality.rawValue
                ].joined(separator: ","))
            }
            return Data(("\u{FEFF}" + rows.joined(separator: "\r\n") + "\r\n").utf8)
        case .gpx:
            var rows = [
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                "<gpx version=\"1.1\" creator=\"LatLong\" xmlns=\"http://www.topografix.com/GPX/1/1\" xmlns:ll=\"urn:com.hgsldswk.latlong:1\">",
                "<metadata><name>\(Self.xml(project))</name></metadata>"
            ]
            for point in ordered {
                let c = point.coordinate
                let time = point.fixTime.map { "<time>\(date.string(from: $0))</time>" } ?? ""
                let accuracy = point.accuracy.map { "<ll:horizontalAccuracyMeters>\(Self.measure($0))</ll:horizontalAccuracyMeters>" } ?? ""
                let longitude = c.longitude == 180 ? -180.0 : c.longitude
                rows.append("<wpt lat=\"\(Self.measure(c.latitude))\" lon=\"\(Self.measure(longitude))\">\(time)<name>\(Self.xml(point.displayName))</name><extensions><ll:seq>\(point.seq)</ll:seq>\(accuracy)<ll:source>\(point.source.rawValue)</ll:source></extensions></wpt>")
            }
            rows.append("</gpx>")
            return Data(rows.joined(separator: "\n").utf8)
        case .kml:
            var rows = [
                "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
                "<kml xmlns=\"http://www.opengis.net/kml/2.2\"><Document><name>\(Self.xml(project))</name>"
            ]
            for point in ordered {
                let c = point.coordinate
                let time = point.fixTime.map { "<TimeStamp><when>\(date.string(from: $0))</when></TimeStamp>" } ?? ""
                let accuracy = point.accuracy.map { Self.kmlField("horizontal_accuracy_m", Self.measure($0)) } ?? ""
                let fields = Self.kmlField("seq", String(point.seq)) + accuracy + Self.kmlField("source", point.source.rawValue)
                rows.append("<Placemark><name>\(Self.xml(point.displayName))</name>\(time)<ExtendedData>\(fields)</ExtendedData><Point><coordinates>\(Self.measure(c.longitude)),\(Self.measure(c.latitude))</coordinates></Point></Placemark>")
            }
            rows.append("</Document></kml>")
            return Data(rows.joined(separator: "\n").utf8)
        }
    }

    private static func measure(_ value: Double) -> String {
        let text = String(value == 0 ? 0 : value)
        let parts = text.split(separator: "e")
        guard parts.count == 2, let exponent = Int(parts[1]) else { return text }
        let sign = value < 0 ? "-" : ""
        let mantissa = parts[0].trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let decimalParts = mantissa.split(separator: ".")
        let digits = decimalParts.joined()
        let point = decimalParts[0].count + exponent
        if point <= 0 { return sign + "0." + String(repeating: "0", count: -point) + digits }
        if point >= digits.count { return sign + digits + String(repeating: "0", count: point - digits.count) }
        return sign + String(digits.prefix(point)) + "." + String(digits.dropFirst(point))
    }

    private static func kmlField(_ name: String, _ value: String) -> String {
        "<Data name=\"\(name)\"><value>\(xml(value))</value></Data>"
    }

    private static func csv(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        let dangerous = trimmed.first.map { "=+-@＝＋－＠".contains($0) } ?? false
        let needsPrefix = dangerous || raw.hasPrefix("\t") || raw.hasPrefix("\r") || raw.hasPrefix("\n")
        let value = needsPrefix ? "'" + raw : raw
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func xml(_ raw: String) -> String {
        let safe = String(String.UnicodeScalarView(raw.unicodeScalars.filter {
            let scalar = $0.value
            return scalar == 9 || scalar == 10 || scalar == 13 ||
                (0x20...0xD7FF).contains(scalar) || (0xE000...0xFFFD).contains(scalar) ||
                (0x10000...0x10FFFF).contains(scalar)
        }))
        return safe.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
