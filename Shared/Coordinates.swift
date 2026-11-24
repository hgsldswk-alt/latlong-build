import Foundation

enum CoordinateFormat: String, CaseIterable {
    case dd, dms

    func text(_ value: Double, latitude: Bool) -> String {
        switch self {
        case .dd:
            return decimal(value == 0 ? 0 : value, places: 6)
        case .dms:
            let total = Int((abs(value) * 36_000).rounded())
            let hemisphere = latitude
                ? (value < 0 ? L.t("hemisphere.south") : L.t("hemisphere.north"))
                : (value < 0 ? L.t("hemisphere.west") : L.t("hemisphere.east"))
            return "\(total / 36_000)° \(total / 600 % 60)′ \(decimal(Double(total % 600) / 10, places: 1))″ \(hemisphere)"
        }
    }
}

func decimal(_ value: Double, places: Int) -> String {
    String(format: "%.*f", locale: Locale(identifier: "en_US_POSIX"), places, value)
}

struct Coordinate: Codable, Equatable, Sendable {
    let latitude: Double
    let longitude: Double

    var isValid: Bool {
        (-90...90).contains(latitude) && (-180...180).contains(longitude)
    }
}

struct Fix: Equatable, Sendable {
    let coordinate: Coordinate
    let accuracy: Double
    let time: Date
    let reduced: Bool

    func isUsable(at now: Date) -> Bool {
        let age = now.timeIntervalSince(time)
        return coordinate.isValid && accuracy.isFinite && accuracy >= 0 && (-2...10).contains(age)
    }

    var quality: Quality { reduced || accuracy > 20 ? .low : .good }
}

enum Quality: String, Codable, CaseIterable, Sendable {
    case good, low, unknown

    var title: String {
        switch self {
        case .good: return L.t("quality.good")
        case .low: return L.t("quality.low")
        case .unknown: return L.t("quality.unknown")
        }
    }
}
