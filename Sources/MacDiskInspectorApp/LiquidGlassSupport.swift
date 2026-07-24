import SwiftUI

extension View {
    @ViewBuilder
    func adaptiveGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func adaptiveProminentGlassButtonStyle() -> some View {
        if #available(macOS 26.0, *) {
            buttonStyle(.glassProminent)
        } else {
            buttonStyle(.borderedProminent)
        }
    }

    @ViewBuilder
    func adaptiveStatusGlass() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .capsule)
        } else {
            background(.thickMaterial, in: Capsule())
        }
    }
}

struct AdaptiveFindingSortPicker: View {
    @Binding var selection: InspectorViewModel.FindingSort

    var body: some View {
        if #available(macOS 26.0, *) {
            LiquidGlassFindingSortPicker(selection: $selection)
        } else {
            Picker("排序", selection: $selection) {
                ForEach(InspectorViewModel.FindingSort.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

@available(macOS 26.0, *)
private struct LiquidGlassFindingSortPicker: View {
    @Binding var selection: InspectorViewModel.FindingSort

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(InspectorViewModel.FindingSort.allCases) { mode in
                    if selection == mode {
                        sortButton(mode)
                            .buttonStyle(.glassProminent)
                    } else {
                        sortButton(mode)
                            .buttonStyle(.glass)
                    }
                }
            }
        }
        .animation(.smooth(duration: 0.25), value: selection)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("排序")
    }

    private func sortButton(_ mode: InspectorViewModel.FindingSort) -> some View {
        Button {
            selection = mode
        } label: {
            Text(mode.rawValue)
                .frame(maxWidth: .infinity)
        }
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
    }
}
