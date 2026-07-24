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
            glassEffect(.regular.interactive(), in: .capsule)
        } else {
            background(.thickMaterial, in: Capsule())
        }
    }

    @ViewBuilder
    func adaptiveFunctionalGlass(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: .rect(cornerRadius: cornerRadius)
            )
        } else {
            background(
                .thickMaterial,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            }
        }
    }
}

struct InspectorBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if !reduceTransparency {
                GeometryReader { proxy in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.29, green: 0.63, blue: 0.53).opacity(0.17),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: min(proxy.size.width, proxy.size.height) * 0.48
                            )
                        )
                        .frame(width: proxy.size.width * 0.72, height: proxy.size.width * 0.72)
                        .offset(x: proxy.size.width * 0.5, y: -proxy.size.height * 0.34)
                        .blur(radius: 44)

                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.84, green: 0.55, blue: 0.25).opacity(0.12),
                                    .clear
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: min(proxy.size.width, proxy.size.height) * 0.42
                            )
                        )
                        .frame(width: proxy.size.width * 0.58, height: proxy.size.width * 0.58)
                        .offset(x: -proxy.size.width * 0.2, y: proxy.size.height * 0.48)
                        .blur(radius: 52)
                }
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
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
    @Namespace private var glassNamespace

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                ForEach(InspectorViewModel.FindingSort.allCases) { mode in
                    if selection == mode {
                        sortButton(mode)
                            .buttonStyle(.glassProminent)
                            .glassEffectID("selected-sort", in: glassNamespace)
                            .glassEffectTransition(.matchedGeometry)
                    } else {
                        sortButton(mode)
                            .buttonStyle(.glass)
                            .glassEffectTransition(.materialize)
                    }
                }
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 1), value: selection)
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
