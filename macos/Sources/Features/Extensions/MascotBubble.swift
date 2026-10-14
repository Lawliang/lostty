#if os(macOS)
import SwiftUI

/// The mascot's speech bubble: what the turn observer knows about the
/// focused pane's conversation (spec §6). Lives in a popover whose arrow
/// points at the axolotl; scrolls once taller than `maxHeight`.
struct MascotBubble: View {
    static let width: CGFloat = 340

    let content: BubbleContent
    let maxHeight: CGFloat

    var body: some View {
        ViewThatFits(in: .vertical) {
            inner
            ScrollView { inner }
        }
        .frame(width: Self.width)
        .frame(maxHeight: maxHeight)
    }

    private var inner: some View {
        VStack(alignment: .leading, spacing: 12) {
            switch content {
            case .waiting:
                Text("…")
                    .font(.system(size: 22, weight: .semibold))
                    .accessibilityLabel("Summarizing")
            case .message(let text):
                Text(text)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            case .notes(let notes):
                NotesView(notes: notes)
            case .failed(let error, let notes):
                Text(error)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let notes { NotesView(notes: notes) }
            }
        }
        .padding(14)
        .frame(width: Self.width, alignment: .leading)
        .textSelection(.enabled)
    }
}

/// The notes in the order the user asked for (spec §6): why you started,
/// what we decided, what's built, what's left, then the last reply in
/// plain words. An empty section is left out.
private struct NotesView: View {
    let notes: ObserverNotes

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !notes.why.isEmpty || !notes.asked.isEmpty {
                section("Why you started this") {
                    if !notes.why.isEmpty { paragraph(notes.why) }
                    bullets(notes.asked)
                }
            }
            if !notes.decided.isEmpty {
                section("What we decided together") { bullets(notes.decided) }
            }
            if !notes.built.isEmpty {
                section(notes.progress.isEmpty ? "What's built" : "What's built (\(notes.progress))") {
                    bullets(notes.built)
                }
            }
            if !notes.left.isEmpty {
                section("What's left") { bullets(notes.left) }
            }
            section("Just now") { paragraph(notes.justNow) }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .semibold))
            content()
        }
    }

    private func paragraph(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bullets(_ items: [String]) -> some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("•")
                Text(item).fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 13))
        }
    }
}
#endif
