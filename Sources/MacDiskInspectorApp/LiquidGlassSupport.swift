import AppKit
import SwiftUI

struct UnifiedWindowChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(for: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(for: nsView)
    }

    private func configureWindow(for view: NSView) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.backgroundColor = .windowBackgroundColor
        }
    }
}

extension View {
    @ViewBuilder
    func adaptiveGlassButtonStyle(controlSize: ControlSize = .regular) -> some View {
        if #available(macOS 26.0, *) {
            self
                .controlSize(controlSize)
                .buttonStyle(.glass)
        } else {
            self
                .controlSize(controlSize)
                .buttonStyle(.bordered)
        }
    }

    @ViewBuilder
    func adaptiveProminentGlassButtonStyle(controlSize: ControlSize = .regular) -> some View {
        if #available(macOS 26.0, *) {
            self
                .controlSize(controlSize)
                .buttonStyle(.glassProminent)
        } else {
            self
                .controlSize(controlSize)
                .buttonStyle(.borderedProminent)
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

    func inspectorContentSurface(cornerRadius: CGFloat = 14) -> some View {
        modifier(InspectorContentSurfaceModifier(cornerRadius: cornerRadius))
    }

    @ViewBuilder
    func adaptiveBackgroundExtension() -> some View {
        if #available(macOS 26.0, *) {
            backgroundExtensionEffect()
        } else {
            self
        }
    }
}

struct InspectorBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)

            if !reduceTransparency && colorScheme == .light {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.clear,
                        Color.black.opacity(0.01)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }

            if !reduceTransparency && colorScheme == .light {
                GeometryReader { proxy in
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [
                                    Color(red: 0.29, green: 0.63, blue: 0.53)
                                        .opacity(0.075),
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
                                    Color(red: 0.84, green: 0.55, blue: 0.25)
                                        .opacity(0.055),
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

private struct InspectorContentSurfaceModifier: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast

    let cornerRadius: CGFloat

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(surfaceStyle)
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(colorSchemeContrast == .increased ? 0.2 : 0.09),
                        lineWidth: 1
                    )
            }
            .overlay(alignment: .top) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .trim(from: 0.06, to: 0.46)
                    .stroke(Color.white.opacity(reduceTransparency ? 0 : 0.2), lineWidth: 0.8)
                    .padding(0.5)
                    .allowsHitTesting(false)
            }
            .shadow(
                color: Color.black.opacity(reduceTransparency ? 0 : 0.055),
                radius: 14,
                y: 5
            )
    }

    private var surfaceStyle: AnyShapeStyle {
        if reduceTransparency || colorSchemeContrast == .increased {
            return AnyShapeStyle(Color(nsColor: .controlBackgroundColor))
        }
        return AnyShapeStyle(Color(nsColor: .controlBackgroundColor).opacity(0.74))
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
        .controlSize(.regular)
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
