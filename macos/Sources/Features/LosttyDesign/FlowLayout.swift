import SwiftUI

/// Lays children left to right and wraps to a new line when the next one
/// doesn't fit (the fix buttons under a checklist row). With no children it
/// takes no space, including its top padding.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var topPadding: CGFloat = 0

    /// Each child's origin, given the children's sizes and the width available.
    static func origins(for sizes: [CGSize], maxWidth: CGFloat, spacing: CGFloat) -> [CGPoint] {
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for size in sizes {
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return origins
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard !subviews.isEmpty else { return .zero }
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let origins = Self.origins(for: sizes, maxWidth: proposal.width ?? .infinity, spacing: spacing)
        let width = zip(origins, sizes).map { origin, size in origin.x + size.width }.max() ?? 0
        let height = zip(origins, sizes).map { origin, size in origin.y + size.height }.max() ?? 0
        return CGSize(width: width, height: height + topPadding)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let origins = Self.origins(for: sizes, maxWidth: bounds.width, spacing: spacing)
        for (subview, origin) in zip(subviews, origins) {
            subview.place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + topPadding + origin.y),
                          proposal: .unspecified)
        }
    }
}
