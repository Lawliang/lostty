#if os(macOS)
import SwiftUI

/// Under the bottom bar after the prompt sharpener rewrote the focused
/// pane's latest prompt: "Sharpened" and what it fixed, opening to what
/// you typed beside what Claude got.
struct SharpenStrip: View {
    @ObservedObject var model: ExtensionSidebarModel
    @ObservedObject private var sharpens = PaneSharpens.shared
    @State private var open = false

    private var chrome: NSColor { model.chromeColor ?? .windowBackgroundColor }
    private var ink: Color { chrome.isLight ? .black : .white }
    private var pane: UUID? { model.focusedSurfaceID }
    private var entry: Sharpener.Entry? { pane.flatMap { sharpens.entries[$0] } }

    var body: some View {
        if let entry, let pane {
            VStack(alignment: .leading, spacing: 8) {
                header(entry, pane: pane)
                if open { sideBySide(entry) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: chrome))
            .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.08)).frame(height: 0.5) }
            .onChange(of: entry.id) { _ in open = false }
        }
    }

    private func header(_ entry: Sharpener.Entry, pane: UUID) -> some View {
        HStack(spacing: 6) {
            Button { open.toggle() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "wand.and.sparkles")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Sharpened")
                        .font(.system(size: 11, weight: .semibold))
                    ForEach(entry.fixed ?? [], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(ink.opacity(0.1)))
                    }
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(ink.opacity(0.5))
                }
                .foregroundStyle(ink.opacity(0.85))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(open ? "Hide the prompts" : "Show what you typed beside what Claude got")
            Spacer(minLength: 0)
            if open {
                Button("Turn off") {
                    Sharpener.isOn = false
                    sharpens.clear(pane)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(ink.opacity(0.55))
                .help("Send prompts as typed. Turn it back on in the Lostty menu.")
            }
            Button { sharpens.clear(pane) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(ink.opacity(0.45))
            .help("Hide")
        }
    }

    private func sideBySide(_ entry: Sharpener.Entry) -> some View {
        HStack(alignment: .top, spacing: 10) {
            column("yours", entry.original, emphasis: 0.55)
            column("sent", entry.sent, emphasis: 0.9)
        }
    }

    private func column(_ title: String, _ text: String, emphasis: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(ink.opacity(0.45))
            ScrollView {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundStyle(ink.opacity(emphasis))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 120)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Rectangle().fill(ink.opacity(0.05)))
    }
}
#endif
