#if os(iOS)
import GhosttyKit
import LosttyRemote
import UIKit

extension Ghostty {
    /// Where a remote terminal's history comes from, and terminals to draw
    /// it on.
    struct ScrollbackSource {
        /// The pane's recent lines, over the open connection.
        let fetch: @MainActor () async -> PaneHistory?
        /// A terminal that looks like this one (font, skin) with no padding
        /// above or below, and talks to nothing.
        let makeView: @MainActor () -> SurfaceView?
    }

    /// A terminal that shows only what it's fed: a block of history.
    final class StillIO: RemoteIO {
        func write(_ bytes: UnsafeRawBufferPointer) {}
        func resize(cols: UInt16, rows: UInt16, widthPx: UInt32, heightPx: UInt32) {}
        func attach(to surface: ghostty_surface_t) {}
        func detach() {}
    }

    /// Scrolls a remote terminal's history on the phone. Scrolling back
    /// reads the pane's lines once and draws them on read-only blocks of
    /// lines laid over the terminal, stacked in order. The finger only ever
    /// moves the blocks: a terminal scrolling its own lines redraws a frame
    /// behind, so text that moved by lines and points at once snapped. A
    /// block that leaves the screen is drawn again, out of sight, with the
    /// lines coming next. Back at the newest line the blocks go, and the
    /// live terminal (which kept updating underneath) shows again. A pane
    /// that scrolls itself (vim, less, copy mode), or one whose size doesn't
    /// match the phone's, gets the wheel as before.
    @MainActor
    final class ScrollbackScroller {
        private unowned let host: SurfaceView
        private let source: ScrollbackSource
        /// The read under way, and scrolling done while it is.
        private var reading: Task<Void, Never>?
        private var waiting: CGFloat = 0
        /// This gesture's read said the wheel is the way, or failed.
        private var usesWheel = false
        /// The blocks, in a layer of their own over the terminal: made on
        /// the first scroll back, then kept (hidden) for the next. Their
        /// size settles a moment after it's set.
        private let stack = UIView()
        private var blocks: [Block] = []
        private var blocksSized = Date.distantPast
        /// Lines per block: a screen and one more, so two cover it.
        private var chunkRows = 0
        /// While shown: the history, where its blocks go, how far back it's
        /// scrolled and which way it last moved.
        private var history: PaneHistory?
        private var placement: HistoryLayout?
        private var offset: CGFloat = 0
        private var backward = true

        private final class Block {
            let view: SurfaceView
            /// The block of the history it shows.
            var chunk: Int?
            init(view: SurfaceView) { self.view = view }
        }

        /// Visible blocks plus one drawn ahead.
        private static let blockCount = 3
        /// Ghostty's padding above the live terminal's first line (its
        /// default `window-padding-y`, unbalanced).
        private static let screenTop: CGFloat = 2

        init(host: SurfaceView, source: ScrollbackSource) {
            self.host = host
            self.source = source
            stack.isUserInteractionEnabled = false
            stack.isHidden = true
        }

        var isShowing: Bool { history != nil }

        /// A new pan: the last one's verdict doesn't carry over.
        func began() {
            if reading == nil { usesWheel = false }
            guard blocks.isEmpty else { return }
            for _ in 0..<Self.blockCount {
                guard let view = source.makeView() else { return }
                view.isUserInteractionEnabled = false
                stack.addSubview(view)
                blocks.append(Block(view: view))
            }
            host.addSubview(stack)
            layoutBlocks()
            setOcclusion(false)
        }

        /// Scrolls `points` (positive is back, toward older lines). False
        /// when the wheel should take it instead.
        func scroll(by points: CGFloat) -> Bool {
            if history != nil {
                move(by: points)
                return true
            }
            if usesWheel { return false }
            if reading != nil {
                waiting += points
                return true
            }
            // Toward newer lines from the newest: nothing here to scroll, but
            // a program in the pane may want the wheel.
            guard points > 0 else { return false }
            waiting = points
            reading = Task { [weak self, source] in
                let history = await source.fetch()
                guard !Task.isCancelled else { return }
                await self?.read(history)
            }
            return true
        }

        /// Back to the live terminal: typing, a tap, or the view going away.
        func leave() {
            reading?.cancel()
            reading = nil
            waiting = 0
            history = nil
            placement = nil
            offset = 0
            stack.isHidden = true
            setOcclusion(false)
            // The next history is another: no block's lines carry over.
            for block in blocks { block.chunk = nil }
        }

        /// The link under `point` (in the host) on the block there, while shown.
        func link(at point: CGPoint) -> URL? {
            guard history != nil else { return nil }
            for block in blocks where block.chunk != nil {
                let inBlock = host.convert(point, to: block.view)
                if block.view.bounds.contains(inBlock) { return block.view.link(at: inBlock) }
            }
            return nil
        }

        /// The stack covers the terminal; the blocks are its width and a
        /// screen and a line tall. A new size means the pane's changed size
        /// too: what was read no longer fits.
        func layout() {
            stack.frame = host.bounds
            layoutBlocks()
        }

        private func layoutBlocks() {
            guard !blocks.isEmpty, let size = host.surfaceSize, size.rows > 0, size.cell_height_px > 0 else { return }
            let rows = Int(size.rows) + 1
            // Half a pixel spare, so the rows come out whole.
            let height = (CGFloat(rows) * CGFloat(size.cell_height_px) + 0.5) / host.contentScaleFactor
            let blockSize = CGSize(width: host.bounds.width, height: height)
            guard rows != chunkRows || blocks[0].view.bounds.size != blockSize else { return }
            leave()
            chunkRows = rows
            for block in blocks {
                block.view.bounds = CGRect(origin: .zero, size: blockSize)
                block.view.sizeDidChange(blockSize)
            }
            blocksSized = Date()
        }

        private func read(_ history: PaneHistory?) async {
            // Blocks sized just now may not have their size yet.
            let age = Date().timeIntervalSince(blocksSized)
            if age < Self.settle { try? await Task.sleep(for: .seconds(Self.settle - age)) }
            guard reading != nil else { return }
            reading = nil
            let pending = waiting
            waiting = 0
            guard let history, show(history) else {
                usesWheel = true
                if pending != 0 { host.wheel(by: pending) }
                return
            }
            move(by: pending)
            // Their first frames draw a moment after they're fed.
            try? await Task.sleep(for: .seconds(Self.firstFrame))
            if self.history != nil { stack.alpha = 1 }
        }

        /// How long new sizes take to reach blocks' terminals, and how long
        /// freshly fed blocks take to draw.
        private static let settle: TimeInterval = 0.1
        private static let firstFrame: TimeInterval = 0.05

        private func show(_ history: PaneHistory) -> Bool {
            guard !history.takesWheel, history.scrollback > 0,
                  let live = host.surfaceSize, live.cell_height_px > 0,
                  Int(live.columns) == history.cols, Int(live.rows) == history.rows,
                  blocks.count == Self.blockCount else { return false }
            for block in blocks {
                guard let surface = block.view.surface else { return false }
                let size = ghostty_surface_size(surface)
                guard Int(size.columns) == history.cols, Int(size.rows) == chunkRows else { return false }
            }
            self.history = history
            placement = HistoryLayout(
                lineHeight: Double(live.cell_height_px) / Double(host.contentScaleFactor),
                lines: history.lines.count, rows: history.rows, chunkRows: chunkRows,
                top: Double(Self.screenTop), height: Double(host.bounds.height))
            offset = 0
            backward = true
            stack.frame = host.bounds
            stack.alpha = 0
            stack.isHidden = false
            setOcclusion(true)
            place()
            return true
        }

        private func move(by points: CGFloat) {
            guard let layout = placement else { return }
            offset += points
            guard offset > 0 else {
                leave()
                return
            }
            offset = CGFloat(layout.clamped(Double(offset)))
            if points != 0 { backward = points > 0 }
            place()
        }

        /// Gives the blocks on screen, and the next one the way it's going,
        /// their lines; then puts each where its lines belong.
        private func place() {
            guard let layout = placement, let history else { return }
            let visible = layout.visibleChunks(offset: Double(offset))
            let ahead = backward ? visible.lowerBound - 1 : visible.upperBound + 1
            var wanted = Array(visible)
            if (0..<layout.chunkCount).contains(ahead) { wanted.append(ahead) }
            for chunk in wanted where !blocks.contains(where: { $0.chunk == chunk }) {
                guard let free = blocks.first(where: { $0.chunk.map { !wanted.contains($0) } ?? true }) else { break }
                feed(free, chunk: chunk, history: history)
            }
            for block in blocks {
                guard let chunk = block.chunk else { continue }
                let top = CGFloat(layout.chunkTop(chunk, offset: Double(offset)))
                block.view.center = CGPoint(x: block.view.bounds.width / 2, y: top + block.view.bounds.height / 2)
            }
        }

        private func feed(_ block: Block, chunk: Int, history: PaneHistory) {
            guard let surface = block.view.surface else { return }
            // The block's last lines go, scrollback and all.
            var bytes = Data("\u{1B}c\u{1B}[3J".utf8)
            bytes.append(history.chunkFeed(chunk, rows: chunkRows))
            bytes.withUnsafeBytes { raw in
                guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
                ghostty_surface_io_feed(surface, base, raw.count)
            }
            block.chunk = chunk
        }

        private func setOcclusion(_ visible: Bool) {
            for block in blocks {
                if let surface = block.view.surface { ghostty_surface_set_occlusion(surface, visible) }
            }
        }
    }
}
#endif
