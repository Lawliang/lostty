#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Lostty

struct CanvasModelTests {
    private let a = UUID(), b = UUID(), c = UUID()
    private let visible = CGRect(x: 50_000, y: 50_000, width: 1200, height: 800)

    @Test func windowsMovingInTogetherMakeRowsCenteredInTheView() {
        let size = CGSize(width: 400, height: 300)
        let frames = CanvasModel().placements(sizes: Array(repeating: size, count: 3), in: visible)
        // Two across, two rows: 800 × 600 around the view's middle (50_600, 50_400).
        #expect(frames == [
            CGRect(x: 50_200, y: 50_100, width: 400, height: 300),
            CGRect(x: 50_600, y: 50_100, width: 400, height: 300),
            CGRect(x: 50_200, y: 50_400, width: 400, height: 300),
        ])
    }

    @Test func aRowIsAsTallAsItsTallestWindow() {
        let frames = CanvasModel().placements(
            sizes: [CGSize(width: 400, height: 300), CGSize(width: 400, height: 500), CGSize(width: 400, height: 300)],
            in: visible)
        #expect(frames[2].minY == frames[0].minY + 500)
    }

    @Test func windowsMovingInGoRightOfCardsTheyWouldCover() {
        var model = CanvasModel()
        model.add(a, frame: CGRect(x: 50_000, y: 49_000, width: 1000, height: 2000))
        let frames = model.placements(sizes: Array(repeating: CGSize(width: 400, height: 300), count: 2), in: visible)
        #expect(frames.map(\.origin) == [CGPoint(x: 51_000, y: 49_000), CGPoint(x: 51_400, y: 49_000)])
    }

    @Test func oneWindowMovingInGoesWhereANewCardWould() {
        let size = CGSize(width: 400, height: 300)
        #expect(CanvasModel().placements(sizes: [size], in: visible) == [CanvasModel().placement(size: size, in: visible)])
    }

    private func model(_ frames: [(UUID, CGRect)]) -> CanvasModel {
        var model = CanvasModel()
        for (id, frame) in frames { model.add(id, frame: frame) }
        return model
    }

    @Test func aCardBesideAnotherGoesToItsRightTheSameSize() {
        let a = UUID()
        let from = CGRect(x: 1000, y: 1000, width: 600, height: 400)
        let model = model([(a, from)])
        #expect(model.placement(beside: a) == CGRect(x: 1600, y: 1000, width: 600, height: 400))
    }

    @Test func aCardBesideAnotherTakesTheFirstFreeSide() {
        let a = UUID(), b = UUID(), c = UUID()
        let from = CGRect(x: 1000, y: 1000, width: 600, height: 400)
        // Right is taken: below.
        var model = model([(a, from), (b, CGRect(x: 1700, y: 1100, width: 300, height: 300))])
        #expect(model.placement(beside: a) == CGRect(x: 1000, y: 1400, width: 600, height: 400))
        // Right and below are taken: left.
        model.add(c, frame: CGRect(x: 1000, y: 1500, width: 600, height: 400))
        #expect(model.placement(beside: a) == CGRect(x: 400, y: 1000, width: 600, height: 400))
    }

    @Test func noCardNoPlaceBeside() {
        #expect(CanvasModel().placement(beside: UUID()) == nil)
    }

    @Test func aNewCardGoesInTheMiddleOfTheView() {
        #expect(CanvasModel().placement(in: visible) == CGRect(x: 50_240, y: 50_150, width: 720, height: 500))
    }

    @Test func aNewCardStepsOffAnotherOnesCorner() {
        let first = CanvasModel().placement(in: visible)
        let model = model([(a, first), (b, first.offsetBy(dx: 32, dy: 32))])
        #expect(model.placement(in: visible).origin == CGPoint(x: first.minX + 64, y: first.minY + 64))
    }

    @Test func cardsStayAtLeastTheMinimumAndInsideTheDocument() {
        #expect(CanvasModel.clamped(CGRect(x: -50, y: 10, width: 100, height: 100)) == CGRect(x: 0, y: 10, width: 320, height: 200))
        let far = CanvasModel.clamped(CGRect(x: 99_900, y: 99_950, width: 720, height: 440))
        #expect(far.maxX == CanvasModel.size && far.maxY == CanvasModel.size)
    }

    @Test func theLastCardIsOnTopForClicksAndBringingForwardMovesIt() {
        var model = model([(a, CGRect(x: 0, y: 0, width: 400, height: 300)), (b, CGRect(x: 100, y: 100, width: 400, height: 300))])
        #expect(model.card(at: CGPoint(x: 150, y: 150)) == b)
        #expect(model.card(at: CGPoint(x: 50, y: 50)) == a)
        #expect(model.card(at: CGPoint(x: 900, y: 900)) == nil)
        model.bringToFront(a)
        #expect(model.cards.map(\.id) == [b, a])
        #expect(model.card(at: CGPoint(x: 150, y: 150)) == a)
        model.remove(a)
        #expect(model.cards.map(\.id) == [b])
    }

    @Test func resizingStopsAtTheMinimumWithoutPushingTheCard() {
        let frame = CGRect(x: 1000, y: 1000, width: 720, height: 440)
        #expect(CanvasModel.resized(frame, edges: .right, by: CGSize(width: 80, height: 0)) == CGRect(x: 1000, y: 1000, width: 800, height: 440))
        #expect(CanvasModel.resized(frame, edges: [.left, .top], by: CGSize(width: 1000, height: 1000)) == CGRect(x: 1400, y: 1240, width: 320, height: 200))
        #expect(CanvasModel.resized(frame, edges: .bottom, by: CGSize(width: 50, height: -1000)) == CGRect(x: 1000, y: 1000, width: 720, height: 200))
    }

    @Test func resizeHandlesLineTheEdgesAndCorners() {
        let bounds = CGRect(x: 0, y: 0, width: 720, height: 440)
        #expect(CanvasModel.handleFrame(for: .left, in: bounds) == CGRect(x: 0, y: 14, width: 6, height: 412))
        #expect(CanvasModel.handleFrame(for: .top, in: bounds) == CGRect(x: 14, y: 0, width: 692, height: 6))
        #expect(CanvasModel.handleFrame(for: [.right, .bottom], in: bounds) == CGRect(x: 706, y: 426, width: 14, height: 14))
        #expect(CanvasModel.handleEdges.count == 8)
    }

    @Test func zoomingToFitShowsEveryCardWithAMargin() {
        #expect(CanvasModel().fitRect == nil)
        let model = model([(a, CGRect(x: 1000, y: 1000, width: 400, height: 300)), (b, CGRect(x: 2000, y: 1500, width: 400, height: 300))])
        #expect(model.fitRect == CGRect(x: 960, y: 960, width: 1480, height: 880))
    }

    @Test func onlyCardsNearTheViewDrawLive() {
        let view = CGRect(x: 10_000, y: 10_000, width: 1000, height: 800)
        let model = model([
            (a, CGRect(x: 10_100, y: 10_100, width: 400, height: 300)),
            // Within half a new card (360) of the view's right edge.
            (b, CGRect(x: 11_200, y: 10_100, width: 400, height: 300)),
            (c, CGRect(x: 13_000, y: 10_100, width: 400, height: 300)),
        ])
        #expect(model.cardsInView(view) == [a, b])
    }

    @Test func neighborsAreTheNearestCardThatWay() {
        let model = model([
            (a, CGRect(x: 1000, y: 1000, width: 400, height: 300)),
            (b, CGRect(x: 1600, y: 1050, width: 400, height: 300)),
            (c, CGRect(x: 1050, y: 2000, width: 400, height: 300)),
        ])
        #expect(model.neighbor(of: a, .right) == b)
        #expect(model.neighbor(of: a, .down) == c)
        #expect(model.neighbor(of: a, .left) == nil)
        #expect(model.neighbor(of: b, .left) == a)
        #expect(model.neighbor(of: c, .up) == a)
    }

    @Test func neighborsCanBeOnlySomeOfTheCards() {
        let model = model([
            (a, CGRect(x: 1000, y: 1000, width: 400, height: 300)),
            (b, CGRect(x: 1600, y: 1000, width: 400, height: 300)),
            (c, CGRect(x: 2200, y: 1000, width: 400, height: 300)),
        ])
        // A ticket (b) between two terminals doesn't stop ⌃⌥⌘→.
        #expect(model.neighbor(of: a, .right, among: [a, c]) == c)
    }

    @Test func aCardGoesBackWhereItStoodInTheStack() {
        var model = model([
            (a, CGRect(x: 0, y: 0, width: 400, height: 300)),
            (b, CGRect(x: 0, y: 0, width: 400, height: 300)),
        ])
        model.insert(c, frame: CGRect(x: 0, y: 0, width: 400, height: 300), at: 1)
        #expect(model.cards.map(\.id) == [a, c, b])
        // Past either end: the front, or the back.
        model.insert(c, frame: CGRect(x: 0, y: 0, width: 400, height: 300), at: 9)
        #expect(model.cards.map(\.id) == [a, b, c])
        model.insert(c, frame: CGRect(x: 0, y: 0, width: 400, height: 300), at: -1)
        #expect(model.cards.map(\.id) == [c, a, b])
    }
}

struct CanvasZoomTests {
    @Test func zoomStaysBetweenAQuarterAndTwice() {
        #expect(CanvasZoom.clamped(0.1) == 0.25)
        #expect(CanvasZoom.clamped(3) == 2)
        #expect(CanvasZoom.clamped(0.8) == 0.8)
    }

    @Test func zoomingToACardShowsAViewportOfItsCenter() {
        let rect = CanvasZoom.rect(centeredOn: CGPoint(x: 1000, y: 800), zoom: 2, viewport: CGSize(width: 1200, height: 800))
        #expect(rect == CGRect(x: 700, y: 600, width: 600, height: 400))
    }

    @Test func aGlideStartsAndEndsExactlyWhereItShould() {
        let from = CanvasView(center: CGPoint(x: 1000, y: 800), zoom: 0.5)
        let to = CanvasView(center: CGPoint(x: 1400, y: 600), zoom: 1)
        #expect(CanvasZoom.view(from: from, to: to, progress: 0) == from)
        #expect(CanvasZoom.view(from: from, to: to, progress: 1) == to)
    }

    @Test func aGlideZoomsAtAnEvenRate() {
        // Halfway from 50% to 200% in time is 100%: the same factor each step.
        let from = CanvasView(center: .zero, zoom: 0.5), to = CanvasView(center: .zero, zoom: 2)
        #expect(abs(CanvasZoom.view(from: from, to: to, progress: 0.5).zoom - 1) < 0.0001)
    }

    @Test func aGlideScalesAboutOnePointThatStaysPutOnScreen() {
        // 50% → 100%: the document point at (600, 400) sits at the same
        // screen spot at the start, the end and everywhere between.
        let viewport = CGSize(width: 1200, height: 800)
        let from = CanvasView(center: CGPoint(x: 1000, y: 800), zoom: 0.5)
        let to = CanvasView(center: CGPoint(x: 800, y: 600), zoom: 1)
        func onScreen(_ point: CGPoint, _ view: CanvasView) -> CGPoint {
            let rect = CanvasZoom.rect(centeredOn: view.center, zoom: view.zoom, viewport: viewport)
            return CGPoint(x: (point.x - rect.minX) * view.zoom, y: (point.y - rect.minY) * view.zoom)
        }
        let pivot = CGPoint(x: 600, y: 400)
        let start = onScreen(pivot, from)
        #expect(start == onScreen(pivot, to))
        for progress in [0.25, 0.5, 0.75] {
            let spot = onScreen(pivot, CanvasZoom.view(from: from, to: to, progress: progress))
            #expect(abs(spot.x - start.x) < 0.001 && abs(spot.y - start.y) < 0.001)
        }
    }

    @Test func aGlideWithNoZoomChangeIsAPlainPan() {
        let from = CanvasView(center: CGPoint(x: 0, y: 0), zoom: 1)
        let to = CanvasView(center: CGPoint(x: 400, y: 200), zoom: 1)
        #expect(CanvasZoom.view(from: from, to: to, progress: 0.5) == CanvasView(center: CGPoint(x: 200, y: 100), zoom: 1))
    }

    @Test func aGlideEasesIntoPlace() {
        #expect(CanvasZoom.eased(0) == 0)
        #expect(CanvasZoom.eased(1) == 1)
        // Most of the way early, the last stretch slow.
        #expect(CanvasZoom.eased(0.5) > 0.8)
        #expect(CanvasZoom.eased(0.25) < CanvasZoom.eased(0.5))
    }

    @Test func aSettledZoomRendersAtTheScreensScaleTimesTheZoom() {
        // Pixels per point follow the zoom; a pane's points don't, so its grid never resizes.
        #expect(CanvasZoom.contentScale(backing: 2, zoom: 2) == 4)
        #expect(CanvasZoom.contentScale(backing: 2, zoom: 0.5) == 1)
        #expect(CanvasZoom.contentScale(backing: 1, zoom: 5) == 2)
    }

    @Test func gridDotsMoveWithThePan() {
        #expect(CanvasGrid.firstDot(origin: .zero, zoom: 1) == .zero)
        #expect(CanvasGrid.firstDot(origin: CGPoint(x: 10, y: 30), zoom: 1) == CGPoint(x: 8, y: 7.125))
        // At 25% the same document point is a quarter as far on screen.
        #expect(CanvasGrid.firstDot(origin: CGPoint(x: 100, y: 0), zoom: 0.25) == CGPoint(x: 2, y: 0))
    }

    @Test func gridDotsKeepTheirSpacingAtEveryZoom() {
        // Half the website's spacing each way, on screen, however zoomed.
        #expect(CanvasGrid.spacing == CGSize(width: 9, height: 12.375))
    }
}

struct CanvasWaitsTests {
    private let a = UUID(), b = UUID(), c = UUID()
    private let t0 = Date(timeIntervalSinceReferenceDate: 0)

    @Test func jumpGoesOldestWaitFirstAndWrapsRound() {
        var waits = CanvasWaits()
        waits.update(awaiting: [b], now: t0)
        waits.update(awaiting: [b, a], now: t0 + 5)
        waits.update(awaiting: [b, a, c], now: t0 + 9)
        let panes: Set<UUID> = [a, b, c]
        #expect(waits.order == [b, a, c])
        #expect(waits.next(after: nil, among: panes) == b)
        #expect(waits.next(after: b, among: panes) == a)
        #expect(waits.next(after: c, among: panes) == b)
    }

    @Test func aPaneThatStopsWaitingLeavesTheOrderAndComesBackLast() {
        var waits = CanvasWaits()
        waits.update(awaiting: [a], now: t0)
        waits.update(awaiting: [a, b], now: t0 + 1)
        waits.update(awaiting: [b], now: t0 + 2)
        #expect(waits.order == [b])
        waits.update(awaiting: [b, a], now: t0 + 3)
        #expect(waits.order == [b, a])
    }

    @Test func nothingWaitingOnTheCanvasMeansNoJump() {
        var waits = CanvasWaits()
        #expect(waits.next(after: nil, among: [a]) == nil)
        // A pane waiting in a normal window isn't the canvas's.
        waits.update(awaiting: [c], now: t0)
        #expect(waits.next(after: nil, among: [a, b]) == nil)
    }
}

struct CanvasSavedTests {
    @Test func theSavedCanvasComesBackAsItWas() throws {
        let saved = CanvasSaved<String>(visible: false, center: CGPoint(x: 50_000, y: 50_400), zoom: 0.5, cards: [
            .init(frame: CGRect(x: 1, y: 2, width: 720, height: 440), tree: "back", focused: nil),
            .init(frame: CGRect(x: 30, y: 40, width: 320, height: 200), tree: "front", focused: "pane"),
        ])
        let data = try JSONEncoder().encode(saved)
        #expect(try JSONDecoder().decode(CanvasSaved<String>.self, from: data) == saved)
    }

    @Test func ticketsComeBackWithTheCanvas() throws {
        let ticket = CanvasTicket(key: "LT-2", summary: "Fix login", kind: .bug, priority: .high, status: .inProgress,
                                  assignee: "Sam", details: "Drops after 8s")
        let saved = CanvasSaved<String>(
            visible: true, center: .zero, zoom: 1, cards: [],
            tickets: [.init(id: UUID(), frame: CGRect(x: 5, y: 6, width: 380, height: 360), ticket: ticket, stack: 0)],
            lastTicketNumber: 4)
        let data = try JSONEncoder().encode(saved)
        let back = try JSONDecoder().decode(CanvasSaved<String>.self, from: data)
        #expect(back == saved)
        #expect(!back.isEmpty)
    }

    @Test func aCanvasSavedBeforeTicketsStillComesBack() throws {
        let json = #"{"visible":false,"center":[0,0],"zoom":1,"cards":[{"frame":[[0,0],[720,500]],"tree":"only"}]}"#
        let saved = try JSONDecoder().decode(CanvasSaved<String>.self, from: Data(json.utf8))
        #expect(saved.cards.map(\.tree) == ["only"])
        #expect(saved.tickets == nil)
        #expect(saved.lastTicketNumber == nil)
        #expect(!saved.isEmpty)
    }

    @Test func aCanvasWithNoCardsOrTicketsIsEmpty() {
        #expect(CanvasSaved<String>(visible: true, center: .zero, zoom: 1, cards: [], tickets: []).isEmpty)
    }
}
#endif
