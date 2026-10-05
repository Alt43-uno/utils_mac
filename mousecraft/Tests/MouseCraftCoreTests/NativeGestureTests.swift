import AppKit
import Testing
import MouseCraftNative

@Suite struct NativeGestureTests {
    // Decode only. These tests never post global events or request permissions.
    @Test func pinchIsDecodedAsMagnifyWithCorrectMagnitudeAndPhases() throws {
        let begin = try #require(NativeGestureEvents.magnify(0, phase: .began).flatMap(NSEvent.init(cgEvent:)))
        let change = try #require(NativeGestureEvents.magnify(0.06, phase: .changed).flatMap(NSEvent.init(cgEvent:)))
        let end = try #require(NativeGestureEvents.magnify(0, phase: .ended).flatMap(NSEvent.init(cgEvent:)))
        #expect(begin.type == .magnify); #expect(begin.phase == .began)
        #expect(change.type == .magnify); #expect(change.phase == .changed)
        #expect(abs(change.magnification - 0.06) < 0.000001)
        #expect(end.phase == .ended)
    }
    @Test func smartZoomIsDecodedAsSmartMagnify() throws {
        let event = try #require(NativeGestureEvents.smartZoom().flatMap(NSEvent.init(cgEvent:)))
        #expect(event.type == .smartMagnify)
    }
    @Test func navigationSwipeIsDecodedAsSwipe() throws {
        let left = try #require(NativeGestureEvents.swipe(left: true, phase: .began).flatMap(NSEvent.init(cgEvent:)))
        let right = try #require(NativeGestureEvents.swipe(left: false, phase: .began).flatMap(NSEvent.init(cgEvent:)))
        #expect(left.type == .swipe); #expect(right.type == .swipe)
        #expect(left.deltaX == -right.deltaX); #expect(left.deltaX != 0)
    }
    @Test func nonFiniteMagnificationIsRejected() { #expect(NativeGestureEvents.magnify(.nan, phase: .changed) == nil) }
}
