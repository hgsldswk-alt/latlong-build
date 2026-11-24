import Foundation
import Security
import StoreKit

actor EntitlementStore {
    private let isolated: Bool
    private let expired: Bool
    private var state: Entitlement?
    private let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.hgsldswk.latlong.entitlement",
        kSecAttrAccount as String: "access"
    ]

    init(isolated: Bool, expired: Bool) {
        self.isolated = isolated
        self.expired = expired
    }

    func refresh(at now: Date, free: Bool, receipt: PurchaseReceipt? = nil) throws -> Entitlement {
        var value = try state ?? load() ?? Entitlement(firstOpen: expired ? now.addingTimeInterval(-31 * 86_400) : now)
        value.beginPaidVersion(at: expired ? value.firstOpen : now, free: free)
        value.latestSeen = value.effectiveDate(now)
        if let receipt { value.apply(receipt) }
        if value != state {
            try save(value)
            state = value
        }
        return value
    }

    private func load() throws -> Entitlement? {
        guard !isolated else { return nil }
        var request = query
        request[kSecReturnData as String] = true
        request[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(request as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw PurchaseError.storage }
        return try JSONDecoder().decode(Entitlement.self, from: data)
    }

    private func save(_ value: Entitlement) throws {
        guard !isolated else { return }
        let data = try JSONEncoder().encode(value)
        let values = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw PurchaseError.storage }
        } else if status != errSecSuccess {
            throw PurchaseError.storage
        }
    }
}

enum PurchaseError: Error { case storage, unverified }

enum StoreProducts {
    static let pro = Bundle.main.object(forInfoDictionaryKey: "LatLongProProductID") as? String ?? "com.hgsldswk.latlong.pro"
    static let trial = Bundle.main.object(forInfoDictionaryKey: "LatLongTrialProductID") as? String ?? "com.hgsldswk.latlong.trial"

    static func receipt(_ transaction: StoreKit.Transaction) -> PurchaseReceipt? {
        let kind: PurchaseReceipt.Kind
        switch transaction.productID {
        case pro: kind = .pro
        case trial: kind = .trial
        default: return nil
        }
        guard transaction.productType == .nonConsumable else { return nil }
        return PurchaseReceipt(kind: kind, originalDate: transaction.originalPurchaseDate,
                               signedAt: transaction.signedDate,
                               revoked: transaction.revocationDate != nil || transaction.isUpgraded)
    }
}
