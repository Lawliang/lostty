#if os(iOS)
import SwiftUI
import UIKit

/// The app's two tabs, in iOS's own tab bar (glass on iOS 26): the Mac's
/// terminals, and Settings.
struct MainTabs: View {
    enum Tab: Hashable { case terminals, settings }

    @EnvironmentObject private var store: MobileStore
    @State private var tab: Tab = .terminals

    var body: some View {
        TabView(selection: $tab) {
            SessionsScreen(openSettings: { tab = .settings })
                .tint(LosttyTheme.accent)
                .tabItem {
                    Label { Text("Terminals") } icon: { Image(uiImage: Self.terminalsIcon) }
                }
                .tag(Tab.terminals)
            NavigationStack { SettingsScreen(inTab: true) }
                .tint(LosttyTheme.accent)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        // The chosen tab in the axolotl's own light pink; the screens keep
        // the app's pink.
        .tint(AxolotlGeometry.skin)
        .onChange(of: tab) { old, _ in
            // Back from Settings, which may have changed the Mac to reach:
            // look again, as closing the Settings sheet did.
            if old == .settings { store.restartWatch() }
        }
    }

    /// Terminals' icon: the axolotl's head, its face (the ">" and "—" eyes
    /// and the little mouth) cut out of it; no body or gills. One color,
    /// which the tab bar tints as it does its symbols.
    static let terminalsIcon: UIImage = {
        // The head spans x 17–83 and y 15–67 of the mascot's 100-unit box.
        let width: CGFloat = 28
        let scale = width / 66
        let size = CGSize(width: width, height: 52 * scale)
        let box = CGRect(x: -17 * scale, y: -15 * scale, width: 100 * scale, height: 100 * scale)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            let ctx = context.cgContext
            ctx.addPath(AxolotlPart(kind: .head).path(in: box).cgPath)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.fillPath()
            ctx.setBlendMode(.clear)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setLineWidth(4.4 * scale)
            ctx.addPath(AxolotlEyes().path(in: box).cgPath)
            ctx.strokePath()
            // A little bolder than the mascot's, to hold up this small.
            ctx.setLineWidth(3.4 * scale)
            ctx.addPath(AxolotlMouth().path(in: box).cgPath)
            ctx.strokePath()
        }
        return image.withRenderingMode(.alwaysTemplate)
    }()
}
#endif
