import SwiftUI
import UIKit

struct CardView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showCoordinates = false
    @State private var showName = false
    @State private var showAccuracy = false
    @State private var rendered: RenderedCard?
    @State private var renderFailed = false
    @State private var retry = 0

    let point: Waypoint?

    private var content: CardContent {
        let coordinates = point.map { point in
            CoordinateFormat.dd.text(point.coordinate.latitude, latitude: true) + ", " +
                CoordinateFormat.dd.text(point.coordinate.longitude, latitude: false)
        }
        return CardContent(
            heading: L.t(point == nil ? "milestone.ten" : "card.meeting"),
            name: showName ? point?.displayName : nil,
            coordinates: showCoordinates ? coordinates : nil,
            accuracy: showAccuracy ? point?.accuracy.map(accuracyText) : nil,
            appName: L.t("app.name"),
            caption: L.t("card.hashtags"),
            qrLabel: L.t("card.qrPlaceholder"),
            storeURL: CardQR.storeURL(Bundle.main.object(forInfoDictionaryKey: "APP_STORE_ID") as? String ?? ""),
            retry: retry
        )
    }

    var body: some View {
        let current = content
        Page {
            if let point {
                Button { model.open(.detail(point.id)) } label: {
                    Text(L.t("point.details")).frame(minHeight: 44).contentShape(Rectangle())
                }
                    .accessibilityIdentifier("card.back")
                VStack(spacing: 2) {
                    Toggle(L.t("card.includeCoordinates"), isOn: $showCoordinates)
                        .frame(minHeight: 44).accessibilityIdentifier("card.coordinates")
                    Toggle(L.t("card.includeName"), isOn: $showName)
                        .frame(minHeight: 44).accessibilityIdentifier("card.name")
                    if point.accuracy != nil {
                        Toggle(L.t("card.includeAccuracy"), isOn: $showAccuracy)
                            .frame(minHeight: 44).accessibilityIdentifier("card.accuracy")
                    }
                }
                .panel(padding: 10)
            }
            if let rendered, rendered.content == current, let image = UIImage(data: rendered.png) {
                Image(uiImage: image)
                    .resizable().scaledToFit().frame(maxWidth: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .frame(maxWidth: .infinity)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(verbatim: rendered.content.accessibilityText))
                    .accessibilityAddTraits(.isImage)
                    .accessibilityIdentifier("card.preview")
                Button(L.t("card.share")) {
                    let caption = L.t(point == nil ? "milestone.caption" : "card.caption") + "\n" + L.t("card.hashtags")
                    model.shareFile(name: "LatLong-card.png", caption: caption) { rendered.png }
                }
                .buttonStyle(FieldButtonStyle(primary: true)).disabled(model.busy)
                .accessibilityIdentifier("card.share")
            } else if renderFailed {
                Button(L.t("card.retry")) { retry += 1 }
                    .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("card.retry")
            } else {
                ProgressView().frame(maxWidth: .infinity, minHeight: 160)
            }
        }
        .navigationTitle(L.t(point == nil ? "milestone.title" : "card.title"))
        .navigationBarTitleDisplayMode(.inline)
        .task(id: current) {
            renderFailed = false
            let png = await Task.detached(priority: .userInitiated) { CardRenderer.png(current) }.value
            guard !Task.isCancelled else { return }
            if let png { rendered = RenderedCard(content: current, png: png) }
            else { renderFailed = true }
        }
    }
}

private struct RenderedCard {
    let content: CardContent
    let png: Data
}
