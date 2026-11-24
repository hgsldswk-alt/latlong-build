import SwiftUI

struct ProjectsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: Project?
    @State private var creating = false

    var body: some View {
        Page {
            if !model.pro { Text(L.t("project.expired")).font(.footnote).foregroundStyle(D.muted) }
            projectRow(nil)
            ForEach(model.library.projects) { project in
                projectRow(project)
            }
            Button(L.t("project.new")) {
                if model.pro { creating = true } else { model.open(.paywall) }
            }
            .buttonStyle(FieldButtonStyle(primary: true))
            .disabled(!model.ready || model.busy)
            .accessibilityIdentifier("project.new")
        }
        .navigationTitle(L.t("project.title"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $creating) {
            NameEditor(title: L.t("project.new"), initial: "", identifier: "project.name", requireName: true) { name in
                guard await model.createProject(name) else { return false }
                model.route = nil
                return true
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(L.t("common.cancel")) { creating = false }.accessibilityIdentifier("editor.cancel")
                }
            }
        }
        .sheet(item: $editing) { project in
            NavigationStack {
                NameEditor(title: L.t("project.rename"), initial: project.name, identifier: "project.name", requireName: true) { name in
                    guard await model.renameProject(project.id, name: name) else { return false }
                    editing = nil
                    return true
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L.t("common.cancel")) { editing = nil }.accessibilityIdentifier("editor.cancel")
                    }
                }
            }
        }
    }

    private func projectRow(_ project: Project?) -> some View {
        let id = project?.id
        return HStack {
            Button {
                if model.pro || id == nil {
                    model.switchCapture(id)
                } else {
                    model.open(.points)
                    model.viewProject(id)
                }
            } label: {
                RowLabel(title: model.library.projectName(id),
                         subtitle: id == model.captureProjectID ? L.t("project.destination") : nil,
                         tail: L.f("points.count", model.library.rows(for: id).count))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(project == nil ? "project.unfiled" : "project.select.\(id?.uuidString ?? "")")
            if let project, model.pro {
                Button { editing = project } label: {
                    Image(systemName: "pencil").frame(width: 44, height: 44)
                }
                .accessibilityLabel(L.t("project.rename"))
                .accessibilityIdentifier("project.rename.\(project.id)")
            }
        }
        .panel(padding: 12)
    }
}

struct PointsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var filtersOpen = false

    var body: some View {
        let rows = model.historyRows
        Page {
            ProjectPicker()
            Button { filtersOpen.toggle() } label: {
                Label(L.t("filter.title"), systemImage: "line.3.horizontal.decrease.circle")
                    .frame(minHeight: 44)
            }
            .accessibilityIdentifier("points.filters")
            if filtersOpen {
                FilterControls(value: $model.historyFilter, prefix: "points", allowQuality: model.canFilterHistoryAccuracy,
                               allowSource: model.pro, showDate: true)
                    .panel(padding: 10)
            }
            HStack {
                Text(L.f("points.count", rows.count)).font(.headline)
                Spacer()
                Text(L.t("points.order")).font(.caption).foregroundStyle(D.muted)
            }
            if rows.isEmpty {
                Text(L.t("points.empty")).foregroundStyle(D.muted).panel()
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { point in
                        HStack(spacing: 8) {
                            Button { model.open(.detail(point.id)) } label: {
                                HStack {
                                    Text(point.number).font(.caption.monospacedDigit().weight(.semibold))
                                        .foregroundStyle(D.teal)
                                    RowLabel(title: point.displayName, subtitle: detail(point))
                                }
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("point.row.\(point.seq)")
                            Button { model.open(.card(point.id)) } label: {
                                Image(systemName: "square.and.arrow.up")
                                    .foregroundStyle(D.teal)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(L.f("card.sharePoint", point.displayName))
                            .accessibilityIdentifier("point.share.\(point.seq)")
                        }
                        .panel(padding: 12)
                    }
                }
            }
            Button(L.t("export.title")) {
                if model.pro || model.library.rows(for: model.viewedProjectID).contains(where: { $0.legacyExport }) {
                    model.open(.export)
                } else {
                    model.open(.paywall)
                }
            }
            .buttonStyle(FieldButtonStyle())
            .accessibilityIdentifier("points.export")
        }
        .navigationTitle(L.t("points.title")).navigationBarTitleDisplayMode(.inline)
    }

    private func detail(_ point: Waypoint) -> String {
        [
            point.savedTime.formatted(date: .abbreviated, time: .shortened),
            point.accuracy.map(accuracyText),
            point.quality == .low ? L.t("quality.low") : nil,
            point.source == .imported ? L.t("source.imported") : nil
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

struct PointDetail: View {
    @EnvironmentObject private var model: AppModel
    @State private var delete = false

    let id: UUID

    var body: some View {
        if let point = model.library.points.first(where: { $0.id == id }) {
            Page {
                Button { model.open(.points) } label: {
                    Text(L.t("points.back")).frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("point.back")
                VStack(alignment: .leading, spacing: 9) {
                    Text(point.displayName).font(.title2.bold()).accessibilityIdentifier("point.title")
                    Text(model.library.projectName(point.projectID) + " · " + point.source.title)
                        .font(.subheadline).foregroundStyle(D.muted)
                    Divider()
                    detailLine("coordinate.latitude", model.format.text(point.coordinate.latitude, latitude: true))
                    detailLine("coordinate.longitude", model.format.text(point.coordinate.longitude, latitude: false))
                    detailLine("coordinate.accuracy", point.accuracy.map(accuracyText) ?? "—")
                    detailLine("coordinate.time", point.fixTime?.formatted(date: .abbreviated, time: .standard) ?? "—")
                    detailLine("point.savedTime", point.savedTime.formatted(date: .abbreviated, time: .shortened))
                    if point.quality == .low { Text(L.t("quality.low")).foregroundStyle(D.amberInk) }
                }
                .panel()
                NavigationLink {
                    NameEditor(title: L.t("point.rename"), initial: point.name, identifier: "point.name", dismissOnSave: true) { name in
                        await model.renamePoint(id, name: name)
                    }
                } label: { Text(L.t("point.rename")) }
                .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("point.rename")
                Button(L.t("home.copy")) { model.copyPoint(point) }
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("point.copy")
                Button(L.t("card.title")) { model.open(.card(point.id)) }
                    .buttonStyle(FieldButtonStyle(primary: true)).accessibilityIdentifier("point.card")
                NavigationLink {
                    CodeView(point: point)
                } label: { Text(L.t("code.open")) }
                .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("point.code")
                Button(role: .destructive) { delete = true } label: {
                    Text(L.t("point.delete")).frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("point.delete")
            }
            .navigationTitle(L.t("point.details")).navigationBarTitleDisplayMode(.inline)
            .alert(L.t("point.deleteConfirm"), isPresented: $delete) {
                Button(L.t("common.cancel"), role: .cancel) {}
                Button(L.t("point.delete"), role: .destructive) { model.deletePoint(id) }
            }
        }
    }

    private func detailLine(_ title: String, _ value: String) -> some View {
        LabeledContent(L.t(title)) { Text(value).monospacedDigit().multilineTextAlignment(.trailing) }
    }
}

struct NameEditor: View {
    let title: String
    let identifier: String
    let requireName: Bool
    let dismissOnSave: Bool
    let save: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var saving = false

    init(title: String, initial: String, identifier: String, requireName: Bool = false,
         dismissOnSave: Bool = false, save: @escaping (String) async -> Bool) {
        self.title = title
        self.identifier = identifier
        self.requireName = requireName
        self.dismissOnSave = dismissOnSave
        self.save = save
        _name = State(initialValue: initial)
    }

    private var valid: Bool { name.count <= 80 && (!requireName || !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }

    var body: some View {
        Page {
            TextField(L.t("name.label"), text: $name)
                .padding(12).background(D.surface, in: RoundedRectangle(cornerRadius: 12))
                .submitLabel(.done).onSubmit(commit).accessibilityIdentifier(identifier)
            if name.count > 80 { Text(L.t("name.invalid")).font(.footnote).foregroundStyle(D.amberInk) }
            Button(L.t("common.save"), action: commit)
                .buttonStyle(FieldButtonStyle(primary: true)).disabled(!valid || saving)
                .accessibilityIdentifier("name.save")
        }
        .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
    }

    private func commit() {
        guard valid, !saving else { return }
        saving = true
        Task {
            let didSave = await save(name)
            saving = false
            if didSave && dismissOnSave { dismiss() }
        }
    }
}

struct ProjectPicker: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Menu {
            Button(L.t("project.unfiled")) { model.viewProject(nil) }.accessibilityIdentifier("project.filter.unfiled")
            ForEach(model.library.projects) { project in
                Button(project.name) { model.viewProject(project.id) }.accessibilityIdentifier("project.filter.\(project.id)")
            }
        } label: {
            RowLabel(title: model.libraryProjectName, subtitle: L.t("project.title")).panel(padding: 12)
        }
        .accessibilityIdentifier("project.picker")
    }
}

struct FilterControls: View {
    @Binding var value: PointFilter
    let prefix: String
    let allowQuality: Bool
    let allowSource: Bool
    var showDate = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if allowQuality {
                Picker(L.t("filter.quality"), selection: $value.quality) {
                    Text(L.t("filter.all")).tag(nil as Quality?)
                    ForEach(Quality.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu).frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier(prefix + ".quality")
            }
            if allowSource {
                Picker(L.t("filter.source"), selection: $value.source) {
                    Text(L.t("filter.all")).tag(nil as PointSource?)
                    ForEach(PointSource.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu).frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier(prefix + ".source")
            }
            if showDate {
                Toggle(L.t("filter.byDate"), isOn: Binding(
                    get: { value.since != nil },
                    set: { value.since = $0 ? Calendar.current.startOfDay(for: Date()) : nil }
                ))
                .frame(minHeight: 44).accessibilityIdentifier(prefix + ".dateEnabled")
                if let date = value.since {
                    DatePicker(L.t("filter.since"), selection: Binding(
                        get: { date }, set: { value.since = Calendar.current.startOfDay(for: $0) }
                    ), displayedComponents: .date)
                    .accessibilityIdentifier(prefix + ".date")
                }
            }
        }
    }
}
