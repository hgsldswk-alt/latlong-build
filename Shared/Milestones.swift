import Foundation

struct Milestones: Codable, Equatable, Sendable {
    var deviceCount = 0
    var firstDay: Date?
    var usedOnAnotherDay = false
    var completedShare = false
    var reviewAttempted = false
    var coreReviewProgress: CoreReviewProgress?

    var hasCard: Bool { deviceCount >= 10 }
    var canRequestReview: Bool { hasCard && usedOnAnotherDay && completedShare && !reviewAttempted }

    mutating func recordDevicePoint(at date: Date, calendar: Calendar = .current) {
        deviceCount += 1
        let today = calendar.startOfDay(for: date)
        if let firstDay {
            if today != firstDay { usedOnAnotherDay = true }
        } else {
            firstDay = today
        }
    }
}
