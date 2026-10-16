import SwiftUI

struct AboutView: View {
    @Environment(\.openURL) var openURL

    private let githubURL = URL(string: "https://github.com/Lawliang/lostty")
    private let ghosttyURL = URL(string: "https://ghostty.org")
    private let docsURL = URL(string: "https://github.com/Lawliang/lostty/tree/main/docs")

    /// Read the commit from the bundle.
    private var build: String? { Bundle.main.infoDictionary?["CFBundleVersion"] as? String }
    private var commit: String? { Bundle.main.infoDictionary?["GhosttyCommit"] as? String }
    private var version: String? { LosttyChannel.displayVersion(info: Bundle.main.infoDictionary) }
    private let copyright = "© 2026 Lawrence Liang"

    #if os(macOS)
    // This creates a background style similar to the Apple "About My Mac" Window
    private struct VisualEffectBackground: NSViewRepresentable {
        let material: NSVisualEffectView.Material
        let blendingMode: NSVisualEffectView.BlendingMode
        let isEmphasized: Bool

        init(material: NSVisualEffectView.Material,
             blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
             isEmphasized: Bool = false) {
            self.material = material
            self.blendingMode = blendingMode
            self.isEmphasized = isEmphasized
        }

        func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
            nsView.material = material
            nsView.blendingMode = blendingMode
            nsView.isEmphasized = isEmphasized
        }

        func makeNSView(context: Context) -> NSVisualEffectView {
            let visualEffect = NSVisualEffectView()
            visualEffect.autoresizingMask = [.width, .height]
            return visualEffect
        }
    }
    #endif

    var body: some View {
        VStack(alignment: .center) {
            Image("LosttyIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 128)
                .accessibilityLabel("Lostty Application Icon")

            VStack(alignment: .center, spacing: 32) {
                VStack(alignment: .center, spacing: 8) {
                    Text(LosttyChannel.current.appName)
                        .bold()
                        .font(.title)
                    Text("Your terminals, on your Mac\nand in your pocket.")
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .font(.caption)
                        .tint(.secondary)
                        .opacity(0.8)
                    if let url = ghosttyURL {
                        Link("Built on Ghostty, by Mitchell Hashimoto and contributors", destination: url)
                            .font(.caption)
                            .opacity(0.8)
                    }
                }
                .textSelection(.enabled)

                VStack(spacing: 2) {
                    if let version {
                        PropertyRow(label: "Version", text: version)
                    }
                    if let build {
                        PropertyRow(label: "Build", text: build)
                    }
                    if let commit, commit != "",
                       let url = githubURL?.appendingPathComponent("/commits/\(commit)") {
                        PropertyRow(label: "Commit", text: commit, url: url)
                    }
                }
                .frame(maxWidth: .infinity)

                HStack(spacing: 8) {
                    if let url = docsURL {
                        Button("Docs") {
                            openURL(url)
                        }
                    }
                    if let url = githubURL {
                        Button("GitHub") {
                            openURL(url)
                        }
                    }
                }

                Text(copyright)
                    .font(.caption)
                    .textSelection(.enabled)
                    .tint(.secondary)
                    .opacity(0.8)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 8)
        .padding(32)
        .frame(minWidth: 256)
        #if os(macOS)
        .background(VisualEffectBackground(material: .underWindowBackground).ignoresSafeArea())
        #endif
    }

    private struct PropertyRow: View {
        private let label: String
        private let text: String
        private let url: URL?

        init(label: String, text: String, url: URL? = nil) {
            self.label = label
            self.text = text
            self.url = url
        }

        @ViewBuilder private var textView: some View {
            Text(text)
                .frame(width: 125, alignment: .leading)
                .padding(.leading, 2)
                .tint(.secondary)
                .opacity(0.8)
                .monospaced()
        }

        var body: some View {
            HStack(spacing: 4) {
                Text(label)
                    .frame(width: 126, alignment: .trailing)
                    .padding(.trailing, 2)
                if let url {
                    Link(destination: url) {
                        textView
                    }
                } else {
                    textView
                }
            }
            .font(.callout)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity)
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}
