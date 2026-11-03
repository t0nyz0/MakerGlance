import AppKit
import MakerPulseCore

@MainActor enum BrandIconAudit {
    static func capture(directory: URL) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            func save(_ image: NSImage, name: String) throws -> Bool {
                let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 512, pixelsHigh: 512, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                image.draw(in: NSRect(x: 0, y: 0, width: 512, height: 512))
                NSGraphicsContext.restoreGraphicsState()
                try rep.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent(name))
                guard let color = rep.colorAt(x: 90, y: 256)?.usingColorSpace(.deviceRGB) else { return false }
                return color.alphaComponent > 0.9 && max(color.redComponent, color.greenComponent, color.blueComponent) < 0.22
            }
            let finder = try save(NSWorkspace.shared.icon(forFile: Bundle.main.bundleURL.path), name: "finder-icon.png")
            let dock = try save(NSApp.applicationIconImage ?? AppGlyph.applicationIcon, name: "running-dock-icon.png")
            let record: [String: Any] = ["displayName": AppIdentity.displayName, "bundleIdentifier": Bundle.main.bundleIdentifier ?? "", "bundlePath": Bundle.main.bundleURL.path,
                "version": Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") ?? "", "build": Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") ?? "",
                "finderIconIsDark": finder, "runningDockImageIsDark": dock, "menuIconIsTemplate": AppGlyph.menu.isTemplate]
            try JSONSerialization.data(withJSONObject: record, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("icon-verification.json"))
        } catch { try? Data(error.localizedDescription.utf8).write(to: directory.appendingPathComponent("icon-error.txt")) }
    }
}
