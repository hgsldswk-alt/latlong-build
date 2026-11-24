import StoreKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@main
struct LatLongApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(D.teal)
                .preferredColorScheme(.light)
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.requestReview) private var requestReview
    @State private var choosingWaypointFile = false
    @State private var readingWaypointFile = false

    var body: some View {
        HomeView(location: model.location, importFile: chooseWaypointFile)
            .overlay(alignment: .bottom) { if model.route == nil { Feedback() } }
            .fileImporter(isPresented: $choosingWaypointFile, allowedContentTypes: [.latLongWaypoint, .plainText]) { result in
                switch result {
                case .success(let url):
                    openWaypointFile(url)
                case .failure(let error):
                    if (error as? CocoaError)?.code != .userCancelled { model.notice = L.t("import.invalid") }
                }
            }
            .sheet(item: $model.route) { route in
                NavigationStack {
                    content(route)
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button(L.t("common.done")) { model.route = nil }
                                    .accessibilityIdentifier("sheet.done")
                            }
                        }
                }
                .tint(D.teal)
                .overlay(alignment: .bottom) { Feedback() }
                .sheet(item: $model.activity, onDismiss: model.dismissedShare) { item in
                    SystemShare(items: item.values) { completed, failed in
                        model.finishedSharing(item, completed: completed, failed: failed)
                    }
                }
            }
            .task { await model.start() }
            .onChange(of: phase, initial: true) { _, value in model.setActive(value == .active) }
            .onChange(of: model.route) { _, _ in model.setActive(phase == .active) }
            .reviewAfterCoreAction(when: model.coreReviewHome && !choosingWaypointFile && !readingWaypointFile) { requestReview() }
            .onChange(of: model.reviewSignal) { _, _ in
                if phase == .active && !choosingWaypointFile && !readingWaypointFile {
                    model.requestSharedReview { requestReview() }
                }
            }
    }

    private func chooseWaypointFile() {
        guard !readingWaypointFile else { return }
        if model.testing, let text = ProcessInfo.processInfo.environment["LATLONG_TEST_FILE"] {
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".latlong")
            do {
                try Data(text.utf8).write(to: file)
                openWaypointFile(file, removeAfterReading: true)
            } catch { model.notice = L.t("import.invalid") }
        } else {
            choosingWaypointFile = true
        }
    }

    private func openWaypointFile(_ url: URL, removeAfterReading: Bool = false) {
        readingWaypointFile = true
        Task {
            defer {
                readingWaypointFile = false
                if removeAfterReading { try? FileManager.default.removeItem(at: url) }
            }
            guard let code = await model.readCodeFile(url), model.route == nil else { return }
            model.open(.importFile(code))
        }
    }

    @ViewBuilder private func content(_ route: Route) -> some View {
        switch route {
        case .projects: ProjectsView()
        case .points: PointsView()
        case .export: ExportView()
        case .settings: SettingsView()
        case .importer: ImportView(initialCode: "")
        case .importFile(let initialCode):
            ImportView(initialCode: initialCode)
        case .paywall: PaywallView()
        case .milestone: CardView(point: nil)
        case .detail(let id): PointDetail(id: id)
        case .rename(let id):
            if let point = model.library.points.first(where: { $0.id == id }) {
                NameEditor(title: L.t("point.rename"), initial: point.name, identifier: "point.name") { name in
                    guard await model.renamePoint(id, name: name) else { return false }
                    model.route = nil
                    return true
                }
            }
        case .card(let id):
            if let point = model.library.points.first(where: { $0.id == id }) { CardView(point: point) }
        }
    }
}

private struct Feedback: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group {
            if model.shareRequested && model.route != nil {
                badge(L.t("share.ready")).accessibilityIdentifier("share.requested")
            } else if let notice = model.notice {
                badge(notice).accessibilityIdentifier("feedback.notice")
            }
        }
        .allowsHitTesting(false)
        .padding(.bottom, 8)
        .task(id: model.notice) {
            guard let notice = model.notice else { return }
            UIAccessibility.post(notification: .announcement, argument: notice)
            try? await Task.sleep(for: .seconds(3))
            if !Task.isCancelled && model.notice == notice { model.notice = nil }
        }
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.footnote.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white)
            .padding(.horizontal, 16).padding(.vertical, 10)
            .background(D.ink, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 20)
    }
}

private struct SystemShare: UIViewControllerRepresentable {
    let items: [Any]
    let finished: (Bool, Bool) -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { _, completed, _, error in
            Task { @MainActor in finished(completed, error != nil) }
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
