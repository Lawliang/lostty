#if os(macOS)
import AppKit
import Testing
@testable import Lostty

@MainActor
struct CanvasZoomScrollTests {
    private func scroll(_ dy: Int32, phase: Int64, command: Bool = true) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)!
        event.flags = command ? .maskCommand : []
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        return NSEvent(cgEvent: event)!
    }

    private func canvas() -> CanvasScrollView {
        let view = CanvasScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        view.magnification = 1
        return view
    }

    private func swipe(_ view: CanvasScrollView, by dy: Int32, command: Bool = true) {
        view.scrollWheel(with: scroll(0, phase: 1, command: command))
        for _ in 0..<10 { view.scrollWheel(with: scroll(dy, phase: 2, command: command)) }
        view.scrollWheel(with: scroll(0, phase: 4, command: command))
    }

    @Test func commandScrollZoomsOneWayAndBack() {
        let view = canvas()
        swipe(view, by: 10)
        let one = view.magnification
        #expect(one != 1)
        swipe(view, by: -10)
        #expect(abs(view.magnification - 1) < 0.001)
        // A 100pt swipe zooms a little, finer than a pinch.
        #expect(abs(one - 1) > 0.1 && abs(one - 1) < 0.5)
    }

    @Test func plainScrollPansInstead() {
        let view = canvas()
        swipe(view, by: 10, command: false)
        #expect(view.magnification == 1)
    }

    @Test func aScrollSoonAfterAPanPansOn() {
        let view = canvas()
        #expect(!view.panCarriesOn())
        swipe(view, by: 10, command: false)
        #expect(view.panCarriesOn())
        #expect(!view.panCarriesOn(now: Date().addingTimeInterval(CanvasScrollView.panCarry + 0.1)))
    }

    private func momentum(_ dy: Int32, phase: Int64) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: dy, wheel2: 0, wheel3: 0)!
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: phase)
        return NSEvent(cgEvent: event)!
    }

    @Test func aPanStillInMotionCarriesOn() {
        let view = canvas()
        swipe(view, by: 10, command: false)
        view.scrollWheel(with: momentum(10, phase: 2))
        #expect(view.drawn != nil)
        #expect(view.panCarriesOn())
    }

    @Test func aClickEndsThePan() {
        let view = canvas()
        swipe(view, by: 10, command: false)
        view.clickEndsPan()
        #expect(!view.panCarriesOn())
    }

    @Test func aClickDropsWhatIsLeftOfTheMomentum() {
        let view = canvas()
        swipe(view, by: 10, command: false)
        view.scrollWheel(with: momentum(10, phase: 2))
        view.clickEndsPan()
        view.scrollWheel(with: momentum(10, phase: 2))
        #expect(view.drawn == nil)
        #expect(!view.panCarriesOn())
    }

    @Test func aNewSwipeAfterAClickPansAgain() {
        let view = canvas()
        swipe(view, by: 10, command: false)
        view.clickEndsPan()
        swipe(view, by: 10, command: false)
        #expect(view.panCarriesOn())
    }

    @Test func meterReadsThePercent() {
        #expect(CanvasZoomMeterState.label(1) == "100%")
        #expect(CanvasZoomMeterState.label(0.755) == "76%")
        #expect(CanvasZoomMeterState.fraction(CanvasZoom.minimum) == 0)
        #expect(CanvasZoomMeterState.fraction(CanvasZoom.maximum) == 1)
    }
}
#endif
