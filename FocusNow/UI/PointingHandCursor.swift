import AppKit
import SwiftUI

private struct PointingHandCursorOverlay: NSViewRepresentable {
    func makeNSView(context: Context) -> CursorView {
        CursorView()
    }

    func updateNSView(_ nsView: CursorView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class CursorView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override var isOpaque: Bool {
        false
    }

    override func resetCursorRects() {
        discardCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

extension View {
    func pointingHandCursor() -> some View {
        overlay {
            PointingHandCursorOverlay()
                .allowsHitTesting(false)
        }
    }
}
