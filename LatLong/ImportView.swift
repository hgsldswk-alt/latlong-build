import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let latLongWaypoint = UTType(exportedAs: "com.hgsldswk.latlong.waypoint", conformingTo: .plainText)
}

struct ImportView: View {
    @EnvironmentObject private var model: AppModel
    @FocusState private var keyboard: Bool
    @State private var text: String
    @State private var choosingFile = false
    @State private var readingFile = false

    private var preview: ShareCode? { try? ShareCode.decode(text) }

    init(initialCode: String) {
        _text = State(initialValue: initialCode)
    }

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 9) {
                Text(L.t("import.received")).font(.headline)
                TextEditor(text: $text)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(minHeight: 100)
                    .padding(5)
                    .background(D.paper, in: RoundedRectangle(cornerRadius: 10))
                    .scrollContentBackground(.hidden)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($keyboard)
                    .accessibilityLabel(L.t("import.received"))
                    .accessibilityIdentifier("import.text")
                ViewThatFits(in: .horizontal) {
                    HStack { paste; fileButton }
                    VStack(alignment: .leading) { paste; fileButton }
                }
            }
            .panel()
            if preview == nil && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(L.t("import.invalid")).foregroundStyle(D.amberInk).accessibilityIdentifier("import.error")
            }
            if let preview {
                VStack(alignment: .leading, spacing: 7) {
                    Text(preview.name ?? L.t("source.imported")).font(.headline).accessibilityIdentifier("import.previewName")
                    Text(L.t("source.imported")).font(.caption).foregroundStyle(D.teal)
                    Text(CoordinateFormat.dd.text(preview.coordinate.latitude, latitude: true) + ", " +
                         CoordinateFormat.dd.text(preview.coordinate.longitude, latitude: false))
                        .font(.system(.body, design: .monospaced))
                    if let accuracy = preview.accuracy { Text(accuracyText(accuracy)).font(.footnote) }
                }
                .panel()
                Button(L.t("import.add")) {
                    Task {
                        keyboard = false
                        if await model.importPoint(preview) { text = "" }
                    }
                }
                .buttonStyle(FieldButtonStyle(primary: true)).disabled(!model.ready || model.busy)
                .accessibilityIdentifier("import.add")
            }
        }
        .navigationTitle(L.t("import.title")).navigationBarTitleDisplayMode(.inline)
        .fileImporter(isPresented: $choosingFile,
                      allowedContentTypes: [.latLongWaypoint, .plainText]) { result in
            switch result {
            case .success(let url):
                readingFile = true
                Task {
                    defer { readingFile = false }
                    let previous = text
                    let content = await model.readCodeFile(url)
                    if text == previous { text = content ?? "" }
                }
            case .failure(let error):
                if (error as? CocoaError)?.code != .userCancelled { model.notice = L.t("import.invalid") }
            }
        }
    }

    private var paste: some View {
        PasteButton(payloadType: String.self) { items in
            if let first = items.first {
                keyboard = false
                text = first
            }
        }
        .labelStyle(.titleOnly).frame(minHeight: 44)
        .accessibilityIdentifier("import.paste")
    }

    private var fileButton: some View {
        Button { keyboard = false; choosingFile = true } label: {
            Text(L.t("import.file")).frame(minHeight: 44).contentShape(Rectangle())
        }
            .disabled(readingFile).accessibilityIdentifier("import.file")
    }
}

struct CodeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var name = false
    @State private var accuracy = false

    let point: Waypoint

    var body: some View {
        Page {
            Text(L.t("code.warning")).font(.subheadline).panel(tint: D.amber, border: D.amberLine)
            if !point.name.isEmpty {
                Toggle(L.t("card.includeName"), isOn: $name)
                    .frame(minHeight: 44).accessibilityIdentifier("code.name")
            }
            if point.accuracy != nil {
                Toggle(L.t("card.includeAccuracy"), isOn: $accuracy)
                    .frame(minHeight: 44).accessibilityIdentifier("code.accuracy")
            }
            Button(L.t("code.copy")) { send(asFile: false) }
                .buttonStyle(FieldButtonStyle(primary: true)).accessibilityIdentifier("code.copy")
            Button(L.t("code.file")) { send(asFile: true) }
                .buttonStyle(FieldButtonStyle()).disabled(model.busy).accessibilityIdentifier("code.file")
        }
        .navigationTitle(L.t("code.open")).navigationBarTitleDisplayMode(.inline)
    }

    private func send(asFile: Bool) {
        let value = ShareCode(coordinate: point.coordinate, name: name ? point.name : nil,
                              accuracy: accuracy ? point.accuracy : nil, quality: accuracy ? point.quality : nil)
        do {
            let text = try value.encode()
            if asFile { model.shareFile(name: "LatLong.latlong") { Data(text.utf8) } }
            else { model.copy(text) }
        } catch {
            model.notice = L.t("code.failed")
        }
    }
}
