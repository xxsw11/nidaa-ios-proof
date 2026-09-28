import SwiftUI
import ProofCore

extension HexColor { var color: Color { let (r,g,b) = rgb;return Color(red: r, green: g, blue: b) } }
extension Color { init(hex: String) { self = (HexColor(hex) ?? HexColor("#101110")!).color } }
private struct PaletteKey: EnvironmentKey { static let defaultValue = Palette.dark }
extension EnvironmentValues { var nidaaPalette: Palette { get { self[PaletteKey.self] } set { self[PaletteKey.self] = newValue } } }

struct NidaaCard<Content: View>: View {
    @Environment(\.nidaaPalette) private var palette
    @ViewBuilder let content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 14, content: content)
            .frame(maxWidth: .infinity, alignment: .leading).padding(18)
            .background(Color(hex: palette.background))
            .overlay(RoundedRectangle(cornerRadius: 24).stroke(palette.ink.color, lineWidth: 1))
    }
}
struct NidaaButton: View {
    @Environment(\.nidaaPalette) private var palette
    let title: String
    var icon = "chevron.left"
    var secondary = false
    var id = ""
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon).font(.body.weight(.semibold))
                .multilineTextAlignment(.center).frame(maxWidth: .infinity, minHeight: 48).padding(10)
                .foregroundStyle(secondary ? palette.ink.color : palette.buttonInk.color)
                .background(secondary ? Color(hex: palette.background) : Color(hex: palette.button))
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(palette.ink.color, lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
}
struct ScreenBody<Content: View>: View {
    @Environment(\.nidaaPalette) private var palette
    @ViewBuilder let content: () -> Content
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 22, content: content).padding(22).frame(maxWidth: 650) }
            .frame(maxWidth: .infinity).background(Color(hex: palette.background)).foregroundStyle(palette.ink.color)
    }
}
struct SimulationNotice: View {
    var authSimulation = false
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label("محاكاة محلية · لا إرسال حقيقي", systemImage: "testtube.2").font(.footnote.weight(.semibold))
            if authSimulation { Text("مصادقة محاكية · Debug Simulator فقط").font(.caption).accessibilityIdentifier("simulatedAuthBanner") }
        }.accessibilityElement(children: .combine)
    }
}
struct Avatar: View {
    @Environment(\.nidaaPalette) private var palette
    @ScaledMetric(relativeTo: .title2) private var size: CGFloat = 52
    let name: String
    var body: some View {
        Text(String(name.prefix(1))).font(.title2.bold()).frame(width: size,height: size)
            .foregroundStyle(palette.buttonInk.color).background(Color(hex: palette.button)).clipShape(RoundedRectangle(cornerRadius: 18))
            .accessibilityHidden(true)
    }
}
