#if os(macOS)
import AppKit
import SwiftUI

enum GuardRequestFacts {
    /// What the guard made of the call: its judgement, not what's approved.
    static func assessment(_ r: GuardRequest) -> [(label: String, value: String)] {
        let c = r.check
        var rows: [(String, String)] = [("Kind", c.groupLabel), ("Why", c.why)]
        if let lost = c.lost { rows.append(("Would lose", lost)) }
        return rows
    }

    static func context(_ r: GuardRequest) -> [(label: String, value: String)] {
        let c = r.check
        var rows: [(String, String)] = [("Folder", c.cwd)]
        if let repo = c.repo { rows.append(("Repo", [repo, c.branch].compactMap { $0 }.joined(separator: " · "))) }
        rows.append(("How it came about", "You prompted it"))
        if let reason = c.reason { rows.append(("The agent says", reason)) }
        return rows
    }

    enum ToolInput: Equatable {
        case text(String)
        case tooLarge(Int)
    }

    /// The whole tool input, shown for every tool but Bash (whose command
    /// is its input).
    static func toolInput(_ c: GuardCheck) -> ToolInput? {
        guard c.tool != "Bash", let input = c.toolInput else { return nil }
        if let bytes = c.toolInputBytes { return .tooLarge(bytes) }
        return .text(input)
    }
}

/// One guard request in full: what the agent wants to run, and why it's
/// critical. Deny is the default; Approve never is (spec §7.4).
struct GuardRequestView: View {
    let id: Int
    var onDone: () -> Void = {}
    @ObservedObject private var runtime = GuardRuntime.shared

    var body: some View {
        if let request = runtime.book.request(id) {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.check.agentName) needs your approval").font(.headline)
                    Text("Request #\(request.id) · \(request.check.tool)").font(.subheadline).foregroundStyle(.secondary)
                }
                inputBox(request.check.input, maxHeight: 160)
                if let whole = GuardRequestFacts.toolInput(request.check) {
                    switch whole {
                    case .text(let text):
                        inputBox(text, maxHeight: 280)
                    case .tooLarge(let bytes):
                        Text("Too large to show (\(bytes) bytes)").font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Approving lets exactly what's shown above through, once, in this pane, within 10 minutes.")
                    .font(.caption).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text("The guard's assessment").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    facts(GuardRequestFacts.assessment(request))
                }
                facts(GuardRequestFacts.context(request))
                HStack {
                    Spacer()
                    if request.state == .pending {
                        Button("Approve") { runtime.approve(id); onDone() }
                        Button("Deny", role: .cancel) { runtime.deny(id); onDone() }
                            .keyboardShortcut(.defaultAction)
                            // Escape denies too; a button holds only one shortcut.
                            .background(Button("") { runtime.deny(id); onDone() }.keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true))
                    } else {
                        Text(request.state.label).foregroundStyle(.secondary)
                        Button("Close") { onDone() }.keyboardShortcut(.cancelAction)
                    }
                }
            }
            .padding(16)
            .frame(width: 520)
        } else {
            Text("This request is gone.").padding(16)
        }
    }

    private func inputBox(_ text: String, maxHeight: CGFloat) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
        }
        .frame(minHeight: 44, maxHeight: maxHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
    }

    private func facts(_ rows: [(label: String, value: String)]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.label).foregroundStyle(.secondary)
                    if row.label == "The agent says" {
                        Text(row.value).italic().textSelection(.enabled)
                    } else {
                        Text(row.value).textSelection(.enabled)
                    }
                }
            }
        }
        .font(.callout)
    }
}

extension GuardRequest.State {
    var label: String {
        switch self {
        case .pending: "Waiting"
        case .approved: "Approved"
        case .used: "Approved and used"
        case .denied: "Denied"
        case .expired: "Lapsed"
        }
    }
}

/// A small window per request, brought to the front when opened again.
@MainActor
enum GuardRequestWindow {
    private static var windows: [Int: NSWindow] = [:]

    static func show(_ id: Int) {
        NSApp.activate(ignoringOtherApps: true)
        if let w = windows[id] {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSPanel(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Lostty Guard · #\(id)"
        w.isReleasedWhenClosed = false
        w.contentView = NSHostingView(rootView: GuardRequestView(id: id) { [weak w] in w?.close() })
        w.center()
        windows[id] = w
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            MainActor.assumeIsolated { windows[id] = nil }
        }
        w.makeKeyAndOrderFront(nil)
    }
}

/// The Branches panel's "Approvals" section: every waiting request, oldest
/// first. Open shows the detail; Deny is one click. No "approve all".
struct GuardApprovalsSection: View {
    @ObservedObject private var runtime = GuardRuntime.shared

    var body: some View {
        let pending = runtime.book.pending
        if !pending.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Approvals").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(pending) { r in
                    HStack(spacing: 8) {
                        Circle().fill(Color.orange).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("#\(r.id) · \(r.check.groupLabel)").font(.caption.weight(.medium))
                            Text(r.check.input).font(.system(.caption, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer(minLength: 4)
                        Button("Open") { GuardRequestWindow.show(r.id) }
                        Button("Deny") { runtime.deny(r.id) }
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
#endif
