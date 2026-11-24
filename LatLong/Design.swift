import SwiftUI

enum D {
    static let paper = Color(red: 0.945, green: 0.961, blue: 0.973)
    static let surface = Color.white
    static let ink = Color(red: 0.063, green: 0.149, blue: 0.208)
    static let muted = Color(red: 0.235, green: 0.341, blue: 0.400)
    static let teal = Color(red: 0, green: 0.408, blue: 0.459)
    static let pale = Color(red: 0.875, green: 0.945, blue: 0.941)
    static let line = Color(red: 0.812, green: 0.875, blue: 0.902)
    static let amberInk = Color(red: 0.475, green: 0.251, blue: 0.047)
    static let amber = Color(red: 1, green: 0.961, blue: 0.894)
    static let amberLine = Color(red: 0.894, green: 0.761, blue: 0.580)
}

extension View {
    func panel(tint: Color = D.surface, border: Color = D.line, padding: CGFloat = 16) -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding)
            .background(tint, in: RoundedRectangle(cornerRadius: 20))
            .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(border, lineWidth: 1).allowsHitTesting(false) }
    }
}

struct FieldButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: primary ? 50 : 44)
            .foregroundStyle(primary ? .white : D.teal)
            .background(primary ? D.teal : D.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(primary ? .clear : D.line, lineWidth: 1) }
            .opacity(!enabled ? 0.48 : configuration.isPressed ? 0.72 : 1)
    }
}

struct Page<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: 520)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(D.paper.ignoresSafeArea())
        .foregroundStyle(D.ink)
    }
}

struct RowLabel: View {
    let title: String
    var subtitle: String? = nil
    var tail: String? = nil
    var arrow = true

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(D.ink)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(D.muted) }
            }
            Spacer(minLength: 0)
            if let tail { Text(tail).font(.caption).foregroundStyle(D.muted) }
            if arrow { Image(systemName: "chevron.right").font(.caption.weight(.semibold)).accessibilityHidden(true) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }
}
