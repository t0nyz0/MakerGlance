import SwiftUI
import AppKit
import MakerPulseCore

private struct AppTextScaleKey: EnvironmentKey { static let defaultValue = 1.0 }
extension EnvironmentValues {
    var appTextScale: Double { get { self[AppTextScaleKey.self] } set { self[AppTextScaleKey.self] = newValue } }
}
enum AppTextStyle {
    case largeTitle, title, title2, title3, headline, body, callout, subheadline, footnote, caption, caption2
    var size: CGFloat {
        switch self { case .largeTitle: 34; case .title: 28; case .title2: 22; case .title3: 20; case .headline, .body, .callout, .subheadline: 13; case .footnote, .caption: 12; case .caption2: 11 }
    }
}
enum AppTypography {
    static func pointSize(_ size: CGFloat, scale: Double) -> CGFloat { CGFloat(TextScalePolicy.pointSize(Double(size), factor: scale)) }
    static func font(size: CGFloat, scale: Double, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: pointSize(size, scale: scale), weight: weight, design: design)
    }
}
private struct AppFontModifier: ViewModifier {
    @Environment(\.appTextScale) var scale
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    func body(content: Content) -> some View { content.font(AppTypography.font(size: size, scale: scale, weight: weight, design: design)) }
}
extension View {
    func appFont(size: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> some View { modifier(AppFontModifier(size: size, weight: weight, design: design)) }
    func appFont(_ style: AppTextStyle, design: Font.Design = .default, weight: Font.Weight? = nil) -> some View { appFont(size: style.size, weight: weight ?? (style == .headline ? .semibold : .regular), design: design) }
}

struct TextSizeSettings: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Surface(inset: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    StudioSectionHeading(title: "Text Size", subtitle: "Adjust text throughout MakerGlance.")
                    Spacer()
                    Text("\(model.state.preferences.textSizePercent)%").appFont(.headline).monospacedDigit()
                    Button("Reset to 100%") { model.setTextSize(100) }.disabled(model.state.preferences.textSizePercent == 100)
                }
                TextSizeSlider(value: Binding(get: { model.state.preferences.textSizePercent }, set: { model.setTextSize($0) })).frame(height: 32)
                HStack { Text("85%"); Spacer(); Text("100% default"); Spacer(); Text("150%") }.appFont(.caption).foregroundStyle(Palette.secondaryText)
                VStack(alignment: .leading, spacing: 10) {
                    Text("LIVE PREVIEW").appFont(.caption2, weight: .semibold).foregroundStyle(Palette.secondaryText)
                    Text("Your creator workspace").appFont(size: 23, weight: .semibold)
                    Text("Models, activity and history — at a size that works for you.").appFont(.body).foregroundStyle(Palette.secondaryText)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
                Text("Changes apply immediately and are saved on this Mac. Images and app icons keep their normal size; larger text uses more rows where needed.").appFont(.caption).foregroundStyle(Palette.secondaryText)
            }
        }
    }
}

struct TextSizeSlider: NSViewRepresentable {
    @Binding var value: Int
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSlider {
        let slider = NSSlider(value: Double(value), minValue: 85, maxValue: 150, target: context.coordinator, action: #selector(Coordinator.changed(_:)))
        slider.numberOfTickMarks = 14; slider.allowsTickMarkValuesOnly = true; slider.isContinuous = true
        slider.identifier = NSUserInterfaceItemIdentifier("text-size-slider")
        slider.setAccessibilityIdentifier("text-size-slider"); slider.setAccessibilityLabel("Text Size, percent")
        return slider
    }
    func updateNSView(_ slider: NSSlider, context: Context) { context.coordinator.parent = self; slider.doubleValue = Double(value) }
    @MainActor final class Coordinator: NSObject {
        var parent: TextSizeSlider
        init(_ parent: TextSizeSlider) { self.parent = parent }
        @objc func changed(_ sender: NSSlider) { parent.value = TextScalePolicy.normalized(Int((sender.doubleValue / 5).rounded()) * 5) }
    }
}
