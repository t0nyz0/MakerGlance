import AppKit
import SwiftUI
import MakerPulseCore

/// Focused native regression using an isolated fictional library only.
@MainActor enum SidebarMoneyAudit {
    static func run(model: AppModel, directory: URL) async throws {
        guard model.isolatedQA else { throw PulseError.incomplete("isolated sidebar verification") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 960), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "MakerGlance Sidebar QA"; window.isReleasedWhenClosed = false
        let root = NSHostingView(rootView: RootView().environmentObject(model).appFont(.body).environment(\.appTextScale, 1).environment(\.accessibilityEnabled, true).tint(Palette.controlFill))
        window.contentView = root; window.center(); window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
        defer { window.close() }
        var account = model.state.account ?? AccountState()
        account.balance = BalanceSample(date: Date(), balance: RewardBalance(regularPoints: 1250, exclusivePoints: 750, cashEstimate: Decimal(string: "1234.56"), cashAvailable: 92, cashPending: 18, currency: "USD"))
        model.state.account = account; model.destination = .overview
        try await Task.sleep(for: .milliseconds(500))

        // SwiftUI's virtual accessibility nodes expose these public selectors
        // without declaring the complete NSAccessibilityProtocol conformance.
        func value(_ object: NSObject, _ name: String) -> Any? {
            let selector = NSSelectorFromString(name)
            return object.responds(to: selector) ? object.perform(selector)?.takeUnretainedValue() : nil
        }
        func flag(_ object: NSObject, _ name: String) -> Bool {
            let selector = NSSelectorFromString(name)
            guard object.responds(to: selector), let implementation = object.method(for: selector) else { return false }
            typealias Getter = @convention(c) (AnyObject, Selector) -> Bool
            return unsafeBitCast(implementation, to: Getter.self)(object, selector)
        }
        func elements(_ object: NSObject, depth: Int = 0) -> [NSObject] {
            guard depth < 30 else { return [] }
            let children = value(object, "accessibilityChildren") as? [NSObject] ?? (object as? NSView)?.subviews ?? []
            return [object] + children.flatMap { elements($0, depth: depth + 1) }
        }
        func row(_ item: Destination) throws -> NSObject {
            guard let element = elements(root).first(where: { value($0, "accessibilityIdentifier") as? String == "sidebar-\(item.rawValue)" && value($0, "accessibilityRole") as? String == "AXButton" }) else {
                let tree = elements(root).map { ["type": String(describing: type(of: $0)), "role": value($0, "accessibilityRole") as? String ?? "", "id": value($0, "accessibilityIdentifier") as? String ?? "", "label": value($0, "accessibilityLabel") as? String ?? ""] }
                try JSONSerialization.data(withJSONObject: tree, options: [.prettyPrinted]).write(to: directory.appendingPathComponent("accessibility-tree.json"))
                throw PulseError.incomplete("sidebar accessibility button \(item.rawValue)")
            }
            return element
        }
        func screenFrame(_ object: NSObject) throws -> NSRect {
            guard object.responds(to: NSSelectorFromString("accessibilityFrame")) else { throw PulseError.incomplete("sidebar geometry") }
            typealias Getter = @convention(c) (AnyObject, Selector) -> NSRect
            let selector = NSSelectorFromString("accessibilityFrame")
            return unsafeBitCast(object.method(for: selector), to: Getter.self)(object, selector)
        }
        func settle() async throws { try await Task.sleep(for: .milliseconds(180)); root.layoutSubtreeIfNeeded(); root.displayIfNeeded() }
        func snapshot(_ name: String) throws {
            root.layoutSubtreeIfNeeded(); root.displayIfNeeded()
            guard let rep = root.bitmapImageRepForCachingDisplay(in: root.bounds) else { throw PulseError.incomplete("sidebar render") }
            root.cacheDisplay(in: root.bounds, to: rep)
            try rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        }
        func click(_ element: NSObject, x: CGFloat) async throws {
            let frame = window.convertFromScreen(try screenFrame(element))
            let point = NSPoint(x: frame.minX + x, y: frame.midY), time = ProcessInfo.processInfo.systemUptime
            guard let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1),
                let up = NSEvent.mouseEvent(with: .leftMouseUp, location: point, modifierFlags: [], timestamp: time + 0.02, windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 0) else { throw PulseError.incomplete("sidebar mouse events") }
            NSApp.postEvent(up, atStart: true); window.sendEvent(down); try await settle()
        }
        func key(_ characters: String, code: UInt16) async throws {
            for type in [NSEvent.EventType.keyDown, .keyUp] {
                guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: characters, charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code) else { throw PulseError.incomplete("sidebar keyboard event") }
                window.sendEvent(event)
            }
            try await settle()
        }
        func focusWithKeyboard(_ item: Destination) async throws -> Bool {
            window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
            window.makeFirstResponder(root)
            try await settle()
            for _ in 0..<24 {
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    guard let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil, characters: "\t", charactersIgnoringModifiers: "\t", isARepeat: false, keyCode: 48) else { throw PulseError.incomplete("sidebar Tab event") }
                    window.sendEvent(event)
                }
                try await Task.sleep(for: .milliseconds(30))
                if flag(try row(item), "isAccessibilityFocused") { return true }
            }
            return false
        }

        var checks: [String: Bool] = [:]
        for theme in [ColorScheme.light, .dark] {
            model.auditScheme = theme; window.appearance = NSAppearance(named: theme == .light ? .aqua : .darkAqua)
            let name = theme == .light ? "light" : "dark"
            for item in Destination.sidebar {
                for region in ["leading", "label", "trailing"] {
                    model.destination = item == .overview ? .settings : .overview; try await settle()
                    let button = try row(item), width = try screenFrame(button).width
                    let x: CGFloat = region == "leading" ? 3 : region == "trailing" ? width - 3 : 65
                    try await click(button, x: x)
                    checks["\(name).\(item.rawValue).\(region)Hit"] = model.destination == item
                }
                model.destination = item == .overview ? .settings : .overview; try await settle()
                let button = try row(item)
                checks["\(name).\(item.rawValue).accessibleLabel"] = value(button, "accessibilityLabel") as? String == item.rawValue
                checks["\(name).\(item.rawValue).accessibilityPress"] = flag(button, "accessibilityPerformPress")
                try await settle()
                checks["\(name).\(item.rawValue).accessibilityNavigates"] = model.destination == item
                checks["\(name).\(item.rawValue).selectedTrait"] = flag(try row(item), "isAccessibilitySelected")
                model.destination = item == .overview ? .settings : .overview; try await settle()
                let focused = try await focusWithKeyboard(item)
                checks["\(name).\(item.rawValue).keyboardFocus"] = focused
                if item == .models { try snapshot("sidebar-focus-\(name)") }
                if focused { try await key(" ", code: 49) }
                checks["\(name).\(item.rawValue).spaceActivates"] = model.destination == item
                model.destination = item == .overview ? .settings : .overview; try await settle()
                let returnFocus = try await focusWithKeyboard(item)
                if returnFocus { try await key("\r", code: 36) }
                checks["\(name).\(item.rawValue).returnActivates"] = model.destination == item
            }
            model.destination = .overview; try await settle(); try snapshot("cash-estimate-dashboard-\(name)")
            model.destination = .rewards; try await settle(); try snapshot("cash-estimate-rewards-\(name)")
        }
        checks["fictionalEstimateUnchanged"] = model.state.account?.balance?.balance.cashEstimate == Decimal(string: "1234.56")
        let report: [String: Any] = ["fictionalDataOnly": true, "networkAndKeychainUsed": false, "checks": checks, "keyWindowWasQA": NSApp.keyWindow === window, "fullKeyboardAccessEnabled": NSApp.isFullKeyboardAccessEnabled, "firstResponderType": window.firstResponder.map { String(describing: type(of: $0)) } ?? "none"]
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("sidebar-money.json"))
        guard checks.values.allSatisfy({ $0 }) else { throw PulseError.incomplete("sidebar check: \(checks.filter { !$0.value }.keys.sorted().joined(separator: ", "))") }
    }
}
