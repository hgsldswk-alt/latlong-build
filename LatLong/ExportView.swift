import SwiftUI

struct ExportView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showFilters = false

    var body: some View {
        let snapshot = model.exportPreview
        Page {
            ProjectPicker()
            VStack(alignment: .leading, spacing: 7) {
                Text(L.f("export.count", snapshot.points.count))
                    .font(.title2.bold()).monospacedDigit().accessibilityIdentifier("export.count")
                Text(L.t("export.order")).font(.footnote).foregroundStyle(D.muted)
                if !model.pro { Text(L.t("export.legacy")).font(.footnote).foregroundStyle(D.muted) }
            }
            .panel()
            Button {
                if model.pro || !model.library.rows(for: model.viewedProjectID).filter(\.legacyExport).isEmpty {
                    showFilters.toggle()
                } else {
                    model.open(.paywall)
                }
            } label: {
                Label(L.t("filter.title"), systemImage: "line.3.horizontal.decrease.circle")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("export.filters")
            if showFilters {
                FilterControls(value: $model.exportFilter, prefix: "export", allowQuality: true, allowSource: model.pro)
                    .panel(padding: 10)
            }
            VStack(alignment: .leading, spacing: 7) {
                Text(L.t("export.fieldsTitle")).font(.headline)
                Text(L.t("export.fields")).font(.footnote).foregroundStyle(D.muted)
            }
            .panel()
            if !model.pro && model.library.rows(for: model.viewedProjectID).allSatisfy({ !$0.legacyExport }) {
                Button(L.t("purchase.title")) { model.open(.paywall) }
                    .buttonStyle(FieldButtonStyle(primary: true)).accessibilityIdentifier("export.unlock")
            } else {
                Button(L.t("export.csv")) { model.export(.csv) }
                    .buttonStyle(FieldButtonStyle(primary: true))
                    .disabled(snapshot.points.isEmpty || model.busy).accessibilityIdentifier("export.csv")
                Button(L.t("export.gpx")) { model.export(.gpx) }
                    .buttonStyle(FieldButtonStyle())
                    .disabled(snapshot.points.isEmpty || model.busy).accessibilityIdentifier("export.gpx")
                Button(L.t("export.kml")) { model.export(.kml) }
                    .buttonStyle(FieldButtonStyle())
                    .disabled(snapshot.points.isEmpty || model.busy).accessibilityIdentifier("export.kml")
            }
        }
        .navigationTitle(L.t("export.title")).navigationBarTitleDisplayMode(.inline)
    }
}
