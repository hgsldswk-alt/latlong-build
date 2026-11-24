import Foundation
import StoreKit
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum Route: Identifiable, Equatable {
    case projects, points, export, settings, importer, paywall, milestone
    case detail(UUID), rename(UUID), card(UUID), importFile(String)

    var id: String {
        switch self {
        case .projects: return "projects"
        case .points: return "points"
        case .export: return "export"
        case .settings: return "settings"
        case .importer: return "import"
        case .importFile: return "import-file"
        case .paywall: return "paywall"
        case .milestone: return "milestone"
        case .detail(let id): return "detail-\(id)"
        case .rename(let id): return "rename-\(id)"
        case .card(let id): return "card-\(id)"
        }
    }
}

struct SharedItems: Identifiable {
    let id = UUID()
    let values: [Any]
    let folder: URL?
}

@MainActor
final class AppModel: ObservableObject {
    let location: LocationSource
    let testing: Bool
    let free: Bool
    let demoOffline: Bool
    @Published var route: Route?
    @Published var activity: SharedItems?
    @Published var notice: String?
    @Published private(set) var shareRequested = false
    @Published private(set) var library = Library()
    @Published private(set) var ready = false
    @Published private(set) var busy = false
    @Published private(set) var libraryFailed = false
    @Published private(set) var accessFailed = false
    @Published private(set) var entitlement: Entitlement?
    @Published private(set) var products: [Product] = []
    @Published private(set) var loadingProducts = false
    @Published private(set) var purchasing = false
    @Published private(set) var saved: Waypoint?
    @Published private(set) var reviewSignal = 0
    @Published var format: CoordinateFormat = .dd
    @Published var exportFilter = PointFilter()
    @Published var historyFilter = PointFilter()
    @Published private(set) var viewedProjectID: UUID?

    private let store: WaypointStore
    private let access: EntitlementStore
    private let openedAt = Date()
    private var booted = false
    private var active = false
    private var activatedBefore = false
    private var reviewWindow = false
    private var lastAction = Date()
    private var lastAccessRefresh = Date.distantPast
    private var lastSave = Date.distantPast
    private var clock: Task<Void, Never>?
    private var observer: Task<Void, Never>?
    private var shareCompleted = false
    private var presentedShare: SharedItems?

    init(arguments: [String] = ProcessInfo.processInfo.arguments) {
        testing = arguments.contains("-ui-testing")
        free = Launch.isFree(arguments: testing ? arguments : [])
        demoOffline = testing && arguments.contains("-offline")
        let expired = testing && arguments.contains("-expired")
        let fixture = testing ? Launch.value("-fix", in: arguments) ?? "good" : nil
        location = LocationSource(fixture: fixture)
        access = EntitlementStore(isolated: testing, expired: expired)
        if testing {
            let session = ProcessInfo.processInfo.environment["LATLONG_TEST_SESSION"].flatMap(UUID.init(uuidString:))
            if !arguments.contains("-reset"), let session {
                let folder = URL.temporaryDirectory.appendingPathComponent("LatLongUITest-\(session.uuidString)")
                store = WaypointStore(file: folder.appendingPathComponent("waypoints.json"))
            } else {
                store = WaypointStore(file: nil, initial: arguments.contains("-demo") ? Self.demo() : Library())
            }
            if arguments.contains("-paywall") { route = .paywall }
        } else {
            let applicationSupport = URL.applicationSupportDirectory
            store = WaypointStore(file: applicationSupport.appendingPathComponent("LatLong/waypoints.json"))
        }
    }

    var pro: Bool { free || entitlement?.hasPro(at: Date(), free: free) == true }
    var captureProjectID: UUID? { pro ? library.activeProjectID : nil }
    var currentProjectName: String { library.projectName(captureProjectID) }
    var libraryProjectName: String { library.projectName(viewedProjectID) }
    var canFilterHistoryAccuracy: Bool {
        pro || viewedProjectID != nil || library.rows(for: nil).contains(where: \.legacyExport)
    }
    var historyRows: [Waypoint] {
        var filter = historyFilter
        if !canFilterHistoryAccuracy { filter.quality = nil }
        if !pro { filter.source = nil }
        return library.rows(for: viewedProjectID, filter: filter)
    }
    var exportPreview: ExportSnapshot {
        var filter = exportFilter
        let allowed = pro
        if !allowed { filter.source = nil }
        return library.export(for: viewedProjectID, filter: filter, pro: allowed)
    }
    var proPrice: String? { products.first(where: { $0.id == StoreProducts.pro })?.displayPrice }
    var trialAvailable: Bool { products.contains(where: { $0.id == StoreProducts.trial && $0.price == 0 }) }
    var trialHasEnded: Bool {
        guard let entitlement else { return false }
        return entitlement.effectiveDate(Date()) >= entitlement.trialEnd
    }

    func start() async {
        guard !booted else { return }
        booted = true
        if testing, let code = ProcessInfo.processInfo.environment["LATLONG_TEST_IMPORT"] {
            UIPasteboard.general.string = code
        }
        await refreshAccess(at: openedAt)
        await loadLibrary()
        guard !free, !testing else { return }
        observer = Task { [weak self] in
            for await result in StoreKit.Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = result, await self.consume(transaction) {
                    await transaction.finish()
                }
            }
        }
        await checkReceipts()
    }

    func loadLibrary() async {
        do {
            library = try await store.load()
            viewedProjectID = library.activeProjectID
            ready = true
            libraryFailed = false
        } catch {
            libraryFailed = true
        }
    }

    func setActive(_ next: Bool) {
        if active != next {
            active = next
            if next {
                reviewWindow = activatedBefore && library.milestones.canRequestReview
                activatedBefore = true
                lastAction = Date()
                clock = Task { [weak self] in
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .seconds(1))
                        guard !Task.isCancelled, let self else { return }
                        await self.idleTick()
                    }
                }
                if !free && !testing && ready {
                    Task { await refreshAccess(); await checkReceipts() }
                }
            } else {
                clock?.cancel()
                clock = nil
                reviewWindow = false
                if !free && entitlement != nil { Task { await refreshAccess() } }
            }
        }
        location.setActive(next && route == nil)
    }

    func open(_ destination: Route, fromHome: Bool = false) {
        interacted()
        shareRequested = false
        if fromHome && (destination == .points || destination == .export) {
            if destination == .export && !pro,
               library.export(for: captureProjectID, filter: PointFilter(), pro: false).points.isEmpty,
               let original = library.activeProjectID,
               !library.export(for: original, filter: PointFilter(), pro: false).points.isEmpty {
                viewedProjectID = original
            } else {
                viewedProjectID = captureProjectID
            }
            if destination == .export && !pro && library.rows(for: viewedProjectID).allSatisfy({ !$0.legacyExport }) {
                if let first = library.projects.first(where: { project in
                    library.rows(for: project.id).contains { $0.legacyExport }
                }) {
                    viewedProjectID = first.id
                } else {
                    route = .paywall
                    return
                }
            }
        }
        route = destination
    }

    func interacted() { lastAction = Date() }

    func saveFix() {
        interacted()
        let now = Date()
        guard ready, !busy, now.timeIntervalSince(lastSave) >= 0.8,
              let fix = location.usableFix(at: now) else { return }
        lastSave = now
        let project = captureProjectID
        let allowed = pro
        busy = true
        Task {
            defer { busy = false }
            do {
                let (updated, point) = try await store.save(fix, now: now, projectID: project, pro: allowed)
                library = updated
                saved = point
                CoreReview.shared.record(updated.milestones.coreReviewProgress)
            } catch LibraryError.duplicate {
                notice = L.t("point.duplicate")
            } catch {
                self.notice = L.t("storage.failed")
            }
        }
    }

    func copyFix() {
        guard let fix = location.usableFix(at: Date()) else { return }
        copy(coordinateText(fix.coordinate, accuracy: fix.accuracy, quality: fix.quality))
    }

    func copyPoint(_ point: Waypoint) {
        copy(coordinateText(point.coordinate, accuracy: point.accuracy, quality: point.quality))
    }

    private func coordinateText(_ coordinate: Coordinate, accuracy: Double?, quality: Quality) -> String {
        let text = format.text(coordinate.latitude, latitude: true) + ", " + format.text(coordinate.longitude, latitude: false)
        if quality == .low {
            return text + " (" + L.f("copy.lowAccuracy", accuracy.map { decimal($0, places: 0) } ?? "—") + ")"
        }
        return text
    }

    func copy(_ text: String) {
        interacted()
        if !testing { UIPasteboard.general.setItems([["public.utf8-plain-text": text]], options: [.localOnly: true]) }
        notice = L.t("copy.done")
    }

    func createProject(_ name: String) async -> Bool {
        guard pro else { open(.paywall); return false }
        return await mutate {
            let updated = try await self.store.createProject(name)
            self.viewedProjectID = updated.activeProjectID
            self.saved = nil
            return updated
        }
    }

    func switchCapture(_ id: UUID?) {
        guard id == nil || pro else { open(.paywall); return }
        if !pro { route = nil; return }
        perform {
            let updated = try await self.store.selectProject(id)
            self.viewedProjectID = id
            self.saved = nil
            self.route = nil
            return updated
        }
    }

    func viewProject(_ id: UUID?) {
        interacted()
        viewedProjectID = id
    }

    func renameProject(_ id: UUID, name: String) async -> Bool {
        guard pro else { open(.paywall); return false }
        return await mutate { try await self.store.renameProject(id, name: name) }
    }

    func renamePoint(_ id: UUID, name: String) async -> Bool {
        await mutate {
            let updated = try await self.store.renamePoint(id, name: name)
            if self.saved?.id == id { self.saved = updated.points.first { $0.id == id } }
            return updated
        }
    }

    func deletePoint(_ id: UUID) {
        perform {
            let updated = try await self.store.deletePoint(id)
            if self.saved?.id == id { self.saved = nil }
            self.route = .points
            return updated
        }
    }

    func importPoint(_ code: ShareCode) async -> Bool {
        let allowed = pro
        return await mutate {
            let updated = try await self.store.add(code, now: Date(), pro: allowed)
            self.viewedProjectID = nil
            self.notice = L.t("import.added")
            return updated
        }
    }

    func readCodeFile(_ url: URL) async -> String? {
        do {
            return try await Task.detached(priority: .userInitiated) {
                try ShareCode.readFile(url)
            }.value
        } catch {
            notice = L.t("import.invalid")
            return nil
        }
    }

    func export(_ format: ExportFormat) {
        let snapshot = exportPreview
        guard !snapshot.points.isEmpty else { if !pro { open(.paywall) }; return }
        let name = "LatLong.\(format.rawValue)"
        shareFile(name: name) { snapshot.data(for: format) }
    }

    func shareFile(name: String, caption: String? = nil, data: @escaping @Sendable () throws -> Data) {
        interacted()
        guard !busy, presentedShare == nil else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    let folder = URL.temporaryDirectory.appendingPathComponent("LatLong-\(UUID().uuidString)", isDirectory: true)
                    do {
                        try LocalFiles.prepare(folder)
                        let url = folder.appendingPathComponent(name)
                        try data().write(to: url, options: [.atomic, .completeFileProtection])
                        return url
                    } catch {
                        try? FileManager.default.removeItem(at: folder)
                        throw error
                    }
                }.value
                let folder = url.deletingLastPathComponent()
                if testing || route == nil {
                    shareRequested = testing && route != nil
                    Self.removeTemporaryFolder(folder)
                } else {
                    var items: [Any] = [url]
                    if let caption { items.append(caption) }
                    let item = SharedItems(values: items, folder: folder)
                    presentedShare = item
                    activity = item
                }
            } catch {
                self.notice = L.t("share.failed")
            }
        }
    }

    func finishedSharing(_ item: SharedItems, completed: Bool, failed: Bool) {
        if presentedShare?.id == item.id { activity = nil }
        if failed { notice = L.t("share.failed") }
        if completed {
            shareCompleted = true
            Task { await recordShareIfNeeded() }
        }
    }

    func dismissedShare() {
        if let folder = presentedShare?.folder { Self.removeTemporaryFolder(folder) }
        presentedShare = nil
        activity = nil
    }

    private static func removeTemporaryFolder(_ folder: URL) {
        Task.detached(priority: .utility) { try? FileManager.default.removeItem(at: folder) }
    }

    private func perform(_ change: @escaping () async throws -> Library) {
        Task { _ = await mutate(change) }
    }

    private func mutate(_ change: () async throws -> Library) async -> Bool {
        interacted()
        guard ready, !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            library = try await change()
            return true
        } catch LibraryError.duplicate {
            notice = L.t("point.duplicate")
        } catch LibraryError.invalidName {
            notice = L.t("name.invalid")
        } catch {
            self.notice = L.t("storage.failed")
        }
        return false
    }

    private func idleTick() async {
        let now = Date()
        if ready, !free, now.timeIntervalSince(lastAccessRefresh) >= 60 { await refreshAccess(at: now) }
        await recordShareIfNeeded()
        guard reviewWindow, library.milestones.canRequestReview, reviewIsIdle else { return }
        reviewWindow = false
        reviewSignal += 1
    }

    func requestSharedReview(_ request: () -> Void) {
        guard reviewIsIdle, library.milestones.canRequestReview, CoreReview.shared.attempt(request) else { return }
        Task { _ = await mutate { try await self.store.markReview(attemptIfEligible: true) } }
    }

    var coreReviewHome: Bool { ready && !busy && active && route == nil && activity == nil && notice == nil }

    private func recordShareIfNeeded() async {
        guard shareCompleted, !busy else { return }
        if await mutate({ try await self.store.completeShare() }) { shareCompleted = false }
    }

    private var reviewIsIdle: Bool { !busy && reviewIsIdleIgnoringBusy }
    private var reviewIsIdleIgnoringBusy: Bool {
        !testing && active && route == nil && activity == nil && notice == nil &&
        location.usableFix(at: Date())?.quality == .good && Date().timeIntervalSince(lastAction) >= 12
    }

    func refreshAccess(at now: Date = Date()) async {
        lastAccessRefresh = Date()
        do {
            entitlement = try await access.refresh(at: now, free: free)
            accessFailed = false
        } catch {
            accessFailed = true
        }
    }

    private func consume(_ transaction: StoreKit.Transaction) async -> Bool {
        guard let receipt = StoreProducts.receipt(transaction) else { return false }
        do {
            entitlement = try await access.refresh(at: Date(), free: free, receipt: receipt)
            accessFailed = false
            return true
        } catch {
            accessFailed = true
            return false
        }
    }

    private func checkReceipts() async {
        for productID in [StoreProducts.pro, StoreProducts.trial] {
            if case .verified(let transaction)? = await StoreKit.Transaction.latest(for: productID) {
                _ = await consume(transaction)
            }
        }
    }

    func loadProducts() async {
        guard !free, !loadingProducts, !testing else { return }
        loadingProducts = true
        defer { loadingProducts = false }
        do { products = try await Product.products(for: [StoreProducts.pro, StoreProducts.trial]) }
        catch { self.products = [] }
    }

    func purchase(trial: Bool) async {
        interacted()
        guard !free, !purchasing, !testing,
              let product = products.first(where: { $0.id == (trial ? StoreProducts.trial : StoreProducts.pro) }),
              product.type == .nonConsumable, !trial || product.price == 0 else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            switch try await product.purchase() {
            case .success(.verified(let transaction)):
                guard await consume(transaction) else { throw PurchaseError.storage }
                await transaction.finish()
                notice = L.t(trial ? "trial.claimed" : "purchase.success")
            case .success(.unverified):
                throw PurchaseError.unverified
            case .pending:
                notice = L.t("purchase.pending")
            case .userCancelled:
                break
            @unknown default:
                break
            }
        } catch {
            self.notice = L.t("purchase.failed")
        }
    }

    func restore() async {
        interacted()
        guard !free, !purchasing, !testing else { return }
        purchasing = true
        defer { purchasing = false }
        do {
            try await AppStore.sync()
            await checkReceipts()
            notice = L.t(accessFailed ? "purchase.failed" : entitlement?.purchasedPro == true || entitlement?.trialClaimedAt != nil ? "restore.done" : "restore.none")
        } catch {
            self.notice = L.t("purchase.failed")
        }
    }

    private static func demo() -> Library {
        let project = Project(name: L.t("demo.project"))
        let now = Date()
        let points = [
            Waypoint(seq: 1, projectID: project.id, coordinate: Coordinate(latitude: 35.713842, longitude: 139.772461),
                     accuracy: 8, fixTime: now, savedTime: now, name: L.t("demo.point1"), source: .device, quality: .good, legacyExport: true),
            Waypoint(seq: 2, projectID: project.id, coordinate: Coordinate(latitude: 35.713900, longitude: 139.772610),
                     accuracy: 38, fixTime: now, savedTime: now, name: L.t("demo.point2"), source: .device, quality: .low, legacyExport: true),
            Waypoint(seq: 3, projectID: project.id, coordinate: Coordinate(latitude: 35.714218, longitude: 139.772837),
                     accuracy: 9, fixTime: now, savedTime: now, name: L.t("demo.point3"), source: .device, quality: .good, legacyExport: true)
        ]
        return Library(projects: [project], points: points, activeProjectID: project.id, nextSequence: 4,
                       milestones: Milestones(deviceCount: 9))
    }
}
