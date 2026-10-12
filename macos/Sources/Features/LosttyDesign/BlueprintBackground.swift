import SwiftUI

/// The icon's blueprint: a faint grid with its circles and diagonals. Only
/// behind hero screens (welcome, pairing, empty states).
struct BlueprintBackground: View {
    var body: some View {
        Canvas { context, size in
            let ink = GraphicsContext.Shading.color(.white.opacity(0.06))
            let step: CGFloat = 32
            var grid = Path()
            var x: CGFloat = 0
            while x <= size.width { grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y <= size.height { grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(grid, with: ink, lineWidth: 1)

            let side = min(size.width, size.height) * 0.8
            let outer = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            var guides = Path()
            guides.addEllipse(in: outer)
            guides.addEllipse(in: outer.insetBy(dx: side * 0.22, dy: side * 0.22))
            guides.move(to: .zero); guides.addLine(to: CGPoint(x: size.width, y: size.height))
            guides.move(to: CGPoint(x: size.width, y: 0)); guides.addLine(to: CGPoint(x: 0, y: size.height))
            context.stroke(guides, with: ink, lineWidth: 1)
        }
        .background(LosttyTheme.background)
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
