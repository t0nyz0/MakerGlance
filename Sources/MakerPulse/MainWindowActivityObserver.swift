import AppKit
import SwiftUI

struct MainWindowActivityObserver: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> WindowObserver {
        WindowObserver(model: model)
    }

    func updateNSView(_ view: WindowObserver, context: Context) {}

    final class WindowObserver: NSView {
        private weak var model: AppModel?
        private var awaitingPresentation = true

        init(model: AppModel) {
            self.model = model
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            let notifications = NotificationCenter.default
            notifications.removeObserver(self)
            guard let window else { return }

            awaitingPresentation = true
            notifications.addObserver(self, selector: #selector(windowPresented), name: NSWindow.didBecomeKeyNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowRestored), name: NSWindow.didDeminiaturizeNotification, object: window)
            notifications.addObserver(self, selector: #selector(presentationEnded), name: NSWindow.willCloseNotification, object: window)
            notifications.addObserver(self, selector: #selector(windowPresented), name: NSApplication.didBecomeActiveNotification, object: NSApp)
            notifications.addObserver(self, selector: #selector(presentationEnded), name: NSApplication.didResignActiveNotification, object: NSApp)
            Task { @MainActor [weak self] in self?.windowPresented() }
        }

        @objc private func windowRestored() {
            awaitingPresentation = true
            windowPresented()
        }

        @objc private func presentationEnded() {
            awaitingPresentation = true
        }

        @objc private func windowPresented() {
            // Focus moving between a sheet or tray panel and an already
            // presented main window is not a new presentation.
            guard awaitingPresentation, NSApp.isActive,
                  let window, window.isVisible, window.isKeyWindow, !window.isMiniaturized else { return }
            awaitingPresentation = false
            model?.activitySurfaceOpened()
        }
    }
}
