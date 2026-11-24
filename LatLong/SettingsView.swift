import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Page {
            Button { model.open(.importer) } label: {
                RowLabel(title: L.t("import.title"), subtitle: L.t("import.methods")).panel(padding: 12)
            }
            .buttonStyle(.plain).accessibilityIdentifier("settings.import")
            if !model.free {
                Button { model.open(.paywall) } label: {
                    RowLabel(title: L.t("purchase.title"), subtitle: purchaseStatus).panel(padding: 12)
                }
                .buttonStyle(.plain).accessibilityIdentifier("settings.purchase")
                Button(L.t("purchase.restore")) { Task { await model.restore() } }
                    .buttonStyle(FieldButtonStyle()).disabled(model.purchasing)
                    .accessibilityIdentifier("settings.restore")
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("help.locationTitle")).font(.headline)
                Text(L.t("help.location")).font(.footnote)
                Text(L.t("help.privacy")).font(.footnote)
            }
            .panel()
        }
        .navigationTitle(L.t("settings.title")).navigationBarTitleDisplayMode(.inline)
    }

    private var purchaseStatus: String {
        if model.entitlement?.purchasedPro == true { return L.t("purchase.owned") }
        if model.trialHasEnded { return L.t("trial.ended") }
        if let value = model.entitlement {
            return L.f("trial.until", value.trialEnd.formatted(date: .abbreviated, time: .shortened))
        }
        return L.t("trial.banner")
    }
}

struct PaywallView: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmTrial = false

    var body: some View {
        Page {
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("purchase.headline")).font(.title2.bold()).accessibilityIdentifier("paywall.title")
                Text(L.t("purchase.benefits")).font(.subheadline)
                if model.entitlement?.purchasedPro == true {
                    Text(L.t("purchase.owned")).font(.subheadline.bold()).foregroundStyle(D.teal)
                } else {
                    Text(model.proPrice.map { L.f("purchase.price", $0) } ??
                         L.t(model.loadingProducts ? "purchase.loading" : "purchase.priceUnavailable"))
                    .font(.footnote).foregroundStyle(D.muted)
                }
            }
            .panel(tint: D.pale)
            VStack(alignment: .leading, spacing: 8) {
                Text(L.t("purchase.freeTitle")).font(.headline)
                Text(L.t("purchase.freeBenefits")).font(.subheadline)
            }
            .panel()
            if model.entitlement?.purchasedPro != true {
                Button(L.t("purchase.buy")) { Task { await model.purchase(trial: false) } }
                    .buttonStyle(FieldButtonStyle(primary: true))
                    .disabled(model.proPrice == nil || model.purchasing).accessibilityIdentifier("paywall.buy")
                if model.proPrice == nil && !model.loadingProducts && !model.testing {
                    Button(L.t("purchase.retry")) { Task { await model.loadProducts() } }
                        .buttonStyle(FieldButtonStyle()).accessibilityIdentifier("paywall.retry")
                }
            }
            Button(L.t("purchase.restore")) { Task { await model.restore() } }
                .buttonStyle(FieldButtonStyle())
                .disabled(model.purchasing)
                .accessibilityIdentifier("paywall.restore")
            if model.entitlement?.purchasedPro != true {
                VStack(alignment: .leading, spacing: 7) {
                    Text(L.t("trial.terms")).font(.footnote)
                    if model.trialHasEnded {
                        Text(L.t("trial.ended")).font(.footnote.weight(.semibold))
                    } else if let entitlement = model.entitlement {
                        Text(L.f("trial.until", entitlement.trialEnd.formatted(date: .abbreviated, time: .shortened)))
                            .font(.footnote)
                    }
                    if model.entitlement?.trialClaimedAt != nil {
                        Text(L.t("trial.claimed")).font(.footnote.weight(.semibold))
                    } else {
                        Button(L.t("trial.claim")) { confirmTrial = true }
                            .buttonStyle(FieldButtonStyle())
                            .disabled(model.purchasing || !model.trialAvailable || model.trialHasEnded)
                            .accessibilityIdentifier("paywall.trial")
                    }
                }
                .panel()
            }
        }
        .navigationTitle(L.t("purchase.title")).navigationBarTitleDisplayMode(.inline)
        .alert(L.t("trial.claim"), isPresented: $confirmTrial) {
            Button(L.t("common.cancel"), role: .cancel) {}
            Button(L.t("trial.confirm")) { Task { await model.purchase(trial: true) } }
        } message: {
            Text(L.t("trial.terms"))
        }
        .task { await model.loadProducts() }
    }
}
