import Foundation

struct Entitlement: Codable, Equatable, Sendable {
    var firstOpen: Date
    var proStartedAt: Date?
    var trialClaimedAt: Date?
    var purchasedPro = false
    var latestSeen: Date?
    var proVerifiedAt: Date?
    var trialVerifiedAt: Date?

    var trialStart: Date {
        let local = proStartedAt ?? firstOpen
        return trialClaimedAt.map { min(local, $0) } ?? local
    }
    var trialEnd: Date { trialStart.addingTimeInterval(30 * 86_400) }

    func effectiveDate(_ now: Date) -> Date { max(now, latestSeen ?? now) }

    func hasPro(at now: Date, free: Bool = Launch.isFree) -> Bool {
        let time = effectiveDate(now)
        return free || purchasedPro || (time >= trialStart && time < trialEnd)
    }

    mutating func beginPaidVersion(at date: Date, free: Bool) {
        if !free && proStartedAt == nil { proStartedAt = date }
        latestSeen = effectiveDate(date)
    }

    mutating func apply(_ receipt: PurchaseReceipt) {
        switch receipt.kind {
        case .pro:
            guard proVerifiedAt.map({ receipt.signedAt >= $0 }) ?? true else { return }
            proVerifiedAt = receipt.signedAt
            purchasedPro = !receipt.revoked
        case .trial:
            guard trialVerifiedAt.map({ receipt.signedAt >= $0 }) ?? true else { return }
            trialVerifiedAt = receipt.signedAt
            trialClaimedAt = receipt.revoked ? nil : receipt.originalDate
        }
    }
}

struct PurchaseReceipt: Sendable {
    enum Kind: Sendable { case pro, trial }
    let kind: Kind
    let originalDate: Date
    let signedAt: Date
    let revoked: Bool
}
