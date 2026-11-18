#if canImport(UIKit)
import SwiftUI

/// A draggable floating button that presents ``NetworkInspectorView`` as a sheet.
///
/// Attach the overlay at the root of a SwiftUI hierarchy so the debug entry point is available on
/// every screen:
///
/// ```swift
/// RootView()
///     .overlay {
///         if let inspector = SwiftKit.shared.networkInspector {
///             NetworkInspectorOverlay(inspector: inspector)
///         }
///     }
/// ```
///
/// The trigger is a circular button that can be dragged anywhere inside the safe area. Its
/// position is persisted in `UserDefaults`, so it survives relaunches. Tapping it presents the
/// inspector sheet, which lists transactions newest-first.
///
/// The inspector records nothing unless ``NetworkInspectorConfiguration/isEnabled`` is `true`.
/// Show this overlay in development builds only.
public struct NetworkInspectorOverlay: View {
    private let inspector: NetworkInspectorProtocol

    @State private var isPresented: Bool
    @State private var dragTranslation: CGSize = .zero
    @State private var isDragging = false

    /// Horizontal button position as a fraction of the available width.
    @AppStorage("SwiftKit.NetworkInspector.buttonX") private var storedX = 0.85
    /// Vertical button position as a fraction of the available height.
    @AppStorage("SwiftKit.NetworkInspector.buttonY") private var storedY = 0.76

    private let layout = NetworkInspectorButtonLayout()

    /// Creates the floating inspector trigger.
    /// - Parameters:
    ///   - inspector: The SDK inspector to display.
    ///   - initiallyPresented: Whether to open the sheet as soon as the overlay appears. Defaults
    ///     to `false`. Use this for launch arguments and UI automation.
    public init(inspector: NetworkInspectorProtocol, initiallyPresented: Bool = false) {
        self.inspector = inspector
        _isPresented = State(initialValue: initiallyPresented)
    }

    public var body: some View {
        GeometryReader { proxy in
            let insets = layoutInsets(for: proxy)
            let center = layout.center(
                unitX: storedX,
                unitY: storedY,
                translation: dragTranslation,
                in: proxy.size,
                insets: insets
            )

            trigger
                .position(center)
                .gesture(dragGesture(in: proxy.size, insets: insets))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Network log")
                .accessibilityHint("Shows recent network requests. Drag to move.")
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { isPresented = true }
        }
        .sheet(isPresented: $isPresented) {
            NavigationView {
                NetworkInspectorView(inspector: inspector)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                isPresented = false
                            }
                        }
                    }
            }
            .navigationViewStyle(.stack)
        }
    }

    // MARK: - Trigger

    private var trigger: some View {
        ZStack {
            Circle()
                .fill(Color.accentColor)

            Image(systemName: "ladybug.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundColor(.white)
        }
        .frame(width: layout.diameter, height: layout.diameter)
        .contentShape(Circle())
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 4)
        .scaleEffect(isDragging ? 1.08 : 1)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }

    // MARK: - Dragging

    private func dragGesture(
        in size: CGSize,
        insets: NetworkInspectorButtonLayout.Insets
    ) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                // Treat movement below the threshold as a tap so the sheet still opens.
                if !isDragging,
                   abs(value.translation.width) > 3 || abs(value.translation.height) > 3 {
                    isDragging = true
                }

                if isDragging {
                    dragTranslation = value.translation
                }
            }
            .onEnded { _ in
                if isDragging {
                    let center = layout.center(
                        unitX: storedX,
                        unitY: storedY,
                        translation: dragTranslation,
                        in: size,
                        insets: insets
                    )

                    if let unit = layout.unitPosition(for: center, in: size) {
                        storedX = unit.x
                        storedY = unit.y
                    }
                } else {
                    isPresented = true
                }

                dragTranslation = .zero
                isDragging = false
            }
    }

    private func layoutInsets(for proxy: GeometryProxy) -> NetworkInspectorButtonLayout.Insets {
        NetworkInspectorButtonLayout.Insets(
            top: proxy.safeAreaInsets.top,
            leading: proxy.safeAreaInsets.leading,
            bottom: proxy.safeAreaInsets.bottom,
            trailing: proxy.safeAreaInsets.trailing
        )
    }
}
#endif
