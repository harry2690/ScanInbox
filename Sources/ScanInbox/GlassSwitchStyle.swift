import SwiftUI

// Approved custom glass switch. The material is native; the switch geometry is app-defined.
struct GlassSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration:ToggleStyleConfiguration) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .spring(duration:0.22)) {
                configuration.isOn.toggle()
            }
        } label: {
            HStack {
                configuration.label
                Spacer()
                ZStack(alignment:configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? Color.blue.opacity(0.85) : Color.white.opacity(0.07))
                        .glassEffect(.regular,in:.capsule)
                    Capsule()
                        .fill(Color.white.opacity(configuration.isOn ? 0.38 : 0.22))
                        .glassEffect(.regular.tint(.white.opacity(0.18)),in:.capsule)
                        .overlay { Capsule().strokeBorder(.white.opacity(0.5),lineWidth:0.6) }
                        .frame(width:27,height:22).padding(3)
                }
                .frame(width:49,height:28)
                .opacity(enabled ? 1 : 0.38)
                .accessibilityHidden(true)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityRepresentation {
            Toggle(isOn:configuration.$isOn) { configuration.label }
                .toggleStyle(.switch)
                .disabled(!enabled)
        }
    }
}
