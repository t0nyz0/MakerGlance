import SwiftUI
import MakerPulseCore

struct AppearanceMenu: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Menu {
            Picker("App appearance", selection: Binding(get: { model.appearance }, set: { model.setAppearance($0) })) {
                ForEach(AppearanceChoice.allCases) { choice in Label(choice.title, systemImage: choice.symbol).tag(choice) }
            }
        } label: { Label("Appearance", systemImage: model.appearance.symbol) }
            .menuStyle(.borderlessButton).foregroundStyle(.primary)
            .padding(.horizontal, 8).padding(.vertical, 5).background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))
            .help("App appearance: \(model.appearance.title). Changes only MakerGlance.")
            .accessibilityLabel("Appearance, currently \(model.appearance.title)")
    }
}

struct AppearanceSettings: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        Surface(inset: 24) {
            VStack(alignment: .leading, spacing: 20) {
                StudioSectionHeading(title: "Appearance", subtitle: "Your choice applies to MakerGlance windows and its menu.")
                HStack(spacing: 14) {
                    ForEach(AppearanceChoice.allCases) { choice in
                        Button { model.setAppearance(choice) } label: {
                            VStack(alignment: .leading, spacing: 12) {
                                ZStack(alignment: .topLeading) {
                                    RoundedRectangle(cornerRadius: 8).fill(choice == .dark ? Color(red: 0.05, green: 0.05, blue: 0.06) : choice == .light ? .white : Color.gray.opacity(0.25))
                                    HStack(spacing: 5) { Circle().frame(width: 4, height: 4); Circle().frame(width: 4, height: 4); Circle().frame(width: 4, height: 4) }.foregroundStyle(Color.gray.opacity(0.55)).padding(9)
                                    HStack(spacing: 7) { RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(width: 23); VStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(Palette.accent.opacity(0.65)).frame(height: 5); RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.2)).frame(height: 18) } }.padding(.horizontal, 9).padding(.top, 24).padding(.bottom, 9)
                                }.frame(height: 74)
                                HStack { Label(choice.title, systemImage: choice.symbol); Spacer(); if model.appearance == choice { Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.accent) } }.appFont(size: 13, weight: .medium)
                            }.padding(12).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.appearance == choice ? Palette.accent : .clear, lineWidth: 1.5))
                        }.buttonStyle(.plain).accessibilityLabel("\(choice.title) appearance").accessibilityAddTraits(model.appearance == choice ? .isSelected : [])
                    }
                }
                Text("System follows your Mac. Light and Dark change this app only.").appFont(size: 12).foregroundStyle(Palette.secondaryText)
            }
        }
    }
}
