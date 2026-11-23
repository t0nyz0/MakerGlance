import AppKit
import SwiftUI

struct TrayActivityObserver: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> WindowObserver {
        WindowObserver(model: model)
    }

    func updateNSView(_ view: WindowObserver, context: Context) {}

    final class WindowObserver: NSView {
        private weak var model: AppModel?
        private var presented = false

        init(model: AppModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let notifications = NotificationCenter.default
            notifications.removeObserver(self)
            presented = false
            guard let window else { return }
            // MenuBarExtra can reuse its panel and SwiftUI content. Watch the
            // panel itself so each presentation counts, even without onAppear.
            for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.didChangeOcclusionStateNotification] {
                notifications.addObserver(self, selector: #selector(checkPresentation), name: name, object: window)
            }
            notifications.addObserver(self, selector: #selector(panelClosed), name: NSWindow.willCloseNotification, object: window)
            checkPresentation()
        }

        @objc private func panelClosed() {
            presented = false
        }

        @objc private func checkPresentation() {
            guard let window, window.isVisible else {
                presented = false
                return
            }
            guard !presented, window.isKeyWindow || window.occlusionState.contains(.visible) else { return }
            presented = true
            Task { @MainActor [weak model] in model?.activitySurfaceOpened() }
        }
    }
}
