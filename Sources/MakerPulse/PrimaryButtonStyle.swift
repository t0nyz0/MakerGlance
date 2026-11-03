import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.appFont(size: 12, weight: .semibold).foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Palette.accent.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7)).opacity(enabled ? 1 : 0.5)
    }
}
