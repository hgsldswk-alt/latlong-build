import SwiftUI
import UIKit

struct HomeView: View {
    @ObservedObject var location: LocationSource
    let importFile: () -> Void
    @EnvironmentObject private var model: AppModel
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var showTrial = false

    var body: some View {
        Page {
            header
            reading
            formatPicker
            if location.state == .low { lowHint }
            actions
            if location.state == .denied {
                Button(L.t("location.openSettings")) {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("location.settings")
            }
            if let saved = model.saved { savedPanel(saved) }
            if model.libraryFailed {
                Button(L.t("storage.retry")) { Task { await model.loadLibrary() } }
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("storage.retry")
            }
            if model.accessFailed {
                Button(L.t("access.retry")) { Task { await model.refreshAccess() } }
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("access.retry")
            }
            project
            if model.library.milestones.hasCard {
                Button { model.open(.milestone) } label: {
                    RowLabel(title: L.t("milestone.title"), subtitle: L.t("milestone.ten")).panel(padding: 12)
                }
                .buttonStyle(.plain).accessibilityIdentifier("home.milestone")
            }
            responsivePair {
                Button(L.t("points.title")) { model.open(.points, fromHome: true) }
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("home.points")
                Button(L.t("export.title")) { model.open(.export, fromHome: true) }
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("home.export")
            }
            .disabled(!model.ready)
            responsivePair {
                Button(L.t("import.title")) { model.open(.importer) }
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("home.import")
                Button(L.t("import.fileHome"), action: importFile)
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("home.importFile")
            }
            .disabled(!model.ready)
            if !model.free && !model.trialHasEnded && model.entitlement?.purchasedPro != true { trial }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.t("app.name")).font(.title.weight(.bold)).accessibilityAddTraits(.isHeader)
                Text(L.t("home.current")).font(.subheadline).foregroundStyle(D.muted)
            }
            Spacer(minLength: 8)
            Button(L.t("settings.title")) { model.open(.settings) }
                .font(.subheadline.weight(.semibold))
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("home.settings")
        }
        .padding(.vertical, 5)
    }

    private var reading: some View {
        let fix = location.fix
        let weak = location.state == .low
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(weak ? D.amberInk : D.teal)
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(weak ? D.amberLine.opacity(0.4) : D.pale, in: Capsule())
                    .accessibilityIdentifier("location.state")
                Spacer(minLength: 4)
                Text(L.t(model.demoOffline ? "coordinate.datumOffline" : "coordinate.datum"))
                    .font(.caption).foregroundStyle(D.muted)
            }
            coordinateLine(L.t("coordinate.latitude"), value: fix.map { model.format.text($0.coordinate.latitude, latitude: true) }, id: "reading.latitude")
            coordinateLine(L.t("coordinate.longitude"), value: fix.map { model.format.text($0.coordinate.longitude, latitude: false) }, id: "reading.longitude")
            Divider()
            responsivePair {
                metric(L.t("coordinate.accuracy"), fix.map { accuracyText($0.accuracy) } ?? "—")
                metric(L.t("coordinate.time"), fix?.time.formatted(date: .omitted, time: .standard) ?? "—")
            }
            if location.state == .noSignal || location.state == .denied {
                Text(L.t(location.state == .denied ? "location.deniedHelp" : "location.clearSky"))
                    .font(.footnote).foregroundStyle(D.muted)
            }
        }
        .panel(tint: weak ? D.amber : D.surface, border: weak ? D.amberLine : D.line)
    }

    private var statusTitle: String {
        switch location.state {
        case .good: return L.t("location.good")
        case .low: return L.t("quality.low")
        case .waiting: return L.t("location.waiting")
        case .noSignal: return L.t("location.noSignal")
        case .denied: return L.t("location.denied")
        }
    }

    private func coordinateLine(_ title: String, value: String?, id: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.subheadline).foregroundStyle(D.muted)
                Spacer(minLength: 0)
                coordinateNumber(value).fixedSize()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline).foregroundStyle(D.muted)
                coordinateNumber(value).minimumScaleFactor(0.6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(value ?? "—")
        .accessibilityIdentifier(id)
    }

    private func coordinateNumber(_ value: String?) -> some View {
        Text(value ?? "—")
            .font(model.format == .dd ? .system(.largeTitle, design: .monospaced).weight(.bold) :
                    .system(.title2, design: .monospaced).weight(.bold))
            .lineLimit(1)
    }

    private func metric(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(D.muted)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var formatPicker: some View {
        responsivePair {
            formatButton(.dd, title: L.t("format.dd"))
            formatButton(.dms, title: L.t("format.dms"))
        }
        .padding(4)
        .background(D.line.opacity(0.48), in: RoundedRectangle(cornerRadius: 15))
    }

    private func formatButton(_ format: CoordinateFormat, title: String) -> some View {
        Button {
            model.interacted()
            model.format = format
        } label: {
            Text(title).font(.subheadline.weight(.semibold))
                .foregroundStyle(model.format == format ? D.teal : D.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(model.format == format ? D.surface : Color.clear, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(model.format == format ? .isSelected : [])
        .accessibilityIdentifier("format." + format.rawValue)
    }

    private var lowHint: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L.t("location.lowTitle")).font(.subheadline.weight(.semibold))
            Text(L.t("location.lowHelp")).font(.footnote)
        }
        .foregroundStyle(D.amberInk)
        .panel(tint: D.amber, border: D.amberLine, padding: 12)
    }

    private var actions: some View {
        responsivePair {
            Button(L.t(location.state == .low ? "location.saveLow" : "home.save")) { model.saveFix() }
                .buttonStyle(FieldButtonStyle(primary: true))
                .disabled(location.fix == nil || !model.ready || model.busy)
                .accessibilityIdentifier("home.save")
            Button(L.t("home.copy")) { model.copyFix() }
                .buttonStyle(FieldButtonStyle()).disabled(location.fix == nil)
                .accessibilityIdentifier("home.copy")
        }
    }

    private func savedPanel(_ point: Waypoint) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L.f("home.saved", point.displayName)).font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("home.saved")
                Text(model.library.projectName(point.projectID) + " · " + point.savedTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(D.muted)
            }
            Spacer(minLength: 0)
            Button(L.t("point.rename")) { model.open(.rename(point.id)) }
                .font(.footnote.weight(.semibold)).frame(minHeight: 44)
                .accessibilityIdentifier("saved.rename")
        }
        .panel(tint: D.pale, padding: 12)
    }

    private var project: some View {
        Button { model.open(.projects) } label: {
            RowLabel(title: model.currentProjectName, subtitle: L.t("project.destination"),
                     tail: L.f("points.count", model.library.rows(for: model.captureProjectID).count))
                .panel(padding: 12)
        }
        .buttonStyle(.plain).disabled(!model.ready)
        .accessibilityIdentifier("home.project")
    }

    private var trial: some View {
        VStack(alignment: .leading, spacing: 5) {
            Divider()
            Button {
                model.interacted()
                showTrial.toggle()
                if showTrial { Task { await model.loadProducts() } }
            } label: {
                Label(L.t("trial.banner"), systemImage: showTrial ? "chevron.down" : "chevron.right")
                    .font(.footnote).frame(minHeight: 44, alignment: .leading)
            }
            .accessibilityIdentifier("trial.toggle")
            if showTrial {
                if let value = model.entitlement {
                    Text(L.f("trial.until", value.trialEnd.formatted(date: .abbreviated, time: .shortened))).font(.footnote)
                }
                Text(L.t("trial.terms")).font(.footnote)
                Text(model.proPrice.map { L.f("purchase.price", $0) } ??
                     L.t(model.loadingProducts ? "purchase.loading" : "purchase.priceUnavailable"))
                    .font(.footnote).foregroundStyle(D.muted)
            }
        }
    }

    private func responsivePair<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
        return layout { content() }
    }
}

func accuracyText(_ accuracy: Double) -> String { L.f("coordinate.meters", decimal(accuracy, places: 0)) }
