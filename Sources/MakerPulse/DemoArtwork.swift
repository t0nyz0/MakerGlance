import AppKit

@MainActor enum DemoArtwork {
    private static var cache: [String: NSImage] = [:]
    static func image(_ raw: String?) -> NSImage? {
        if CommandLine.arguments.contains("--qa-library"), let raw, ["demo://hit-portrait", "demo://hit-landscape"].contains(raw) {
            if let image = cache[raw] { return image }
            let size = raw.hasSuffix("portrait") ? NSSize(width: 240,height:1200) : NSSize(width:1200,height:240)
            let image = NSImage(size:size,flipped:false) { rect in
                NSColor.systemOrange.setFill();rect.fill()
                NSColor.darkGray.setFill();NSBezierPath(roundedRect:rect.insetBy(dx:20,dy:20),xRadius:20,yRadius:20).fill()
                return true
            }
            cache[raw] = image;return image
        }
        guard let raw, raw.hasPrefix("demo://"), let key = raw.components(separatedBy: "://").last,
              let index = ["planter", "tray", "clip", "stand", "organizer", "lamp", "rack", "grid", "vase", "avatar"].firstIndex(of: key) else { return nil }
        if let image = cache[key] { return image }
        let image = NSImage(size: NSSize(width: 480, height: 360)); image.lockFocus()
        let colors: [NSColor] = [.systemOrange, .systemBlue, .systemTeal, .systemPurple, .systemPink, .systemYellow, .systemCyan, .systemIndigo, .systemMint, .systemIndigo]
        let tint = colors[index]
        NSGradient(starting: NSColor(calibratedWhite: 0.16, alpha: 1), ending: NSColor(calibratedWhite: 0.08, alpha: 1))!.draw(in: NSRect(x: 0, y: 0, width: 480, height: 360), angle: -50)
        let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.45); shadow.shadowBlurRadius = 30; shadow.shadowOffset = NSSize(width: 0, height: -16); shadow.set()
        func rounded(_ rect: NSRect, radius: CGFloat, color: NSColor) { color.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill() }
        func polygon(_ points: [NSPoint], color: NSColor) { let p = NSBezierPath(); p.move(to: points[0]); points.dropFirst().forEach { p.line(to: $0) }; p.close(); color.setFill(); p.fill() }
        if key == "avatar" {
            rounded(NSRect(x: 140, y: 80, width: 200, height: 200), radius: 70, color: tint)
            ("M" as NSString).draw(at: NSPoint(x: 188, y: 112), withAttributes: [.font: NSFont.systemFont(ofSize: 130, weight: .semibold), .foregroundColor: NSColor.white])
        } else if ["planter", "vase", "lamp"].contains(key) {
            rounded(NSRect(x: 153, y: 80, width: 174, height: 168), radius: key == "vase" ? 75 : 28, color: tint.withAlphaComponent(0.8))
            tint.blended(withFraction: 0.35, of: .white)!.setFill(); NSBezierPath(ovalIn: NSRect(x: 153, y: 220, width: 174, height: 52)).fill()
            NSColor(calibratedWhite: 0.12, alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 166, y: 230, width: 148, height: 30)).fill()
            for n in 0..<12 { tint.blended(withFraction: 0.3, of: .white)!.withAlphaComponent(0.35).setStroke(); let p = NSBezierPath(); p.move(to: NSPoint(x: 164 + n * 13, y: 100)); p.line(to: NSPoint(x: 164 + n * 13, y: 216)); p.lineWidth = 2; p.stroke() }
        } else if key == "clip" || key == "stand" {
            for n in 0..<3 {
                let x = CGFloat(105 + n * 88), y = CGFloat(105 + n * 18)
                rounded(NSRect(x: x, y: y, width: 84, height: 142), radius: 34, color: tint)
                rounded(NSRect(x: x + 20, y: y + 26, width: 44, height: 95), radius: 20, color: NSColor(calibratedWhite: 0.12, alpha: 1))
            }
        } else {
            polygon([NSPoint(x: 84,y: 117),NSPoint(x: 299,y: 82),NSPoint(x: 398,y: 171),NSPoint(x: 180,y: 211)], color: tint)
            polygon([NSPoint(x: 84,y: 117),NSPoint(x: 84,y: 171),NSPoint(x: 180,y: 261),NSPoint(x: 180,y: 211)], color: tint.blended(withFraction: 0.25, of: .black)!)
            polygon([NSPoint(x: 180,y: 211),NSPoint(x: 180,y: 261),NSPoint(x: 398,y: 222),NSPoint(x: 398,y: 171)], color: tint.blended(withFraction: 0.35, of: .white)!)
            if key != "tray" { for n in 0..<4 { rounded(NSRect(x: 150 + n * 40, y: 151 + n * 6, width: 21, height: 28), radius: 5, color: .black.withAlphaComponent(0.35)) } }
        }
        NSShadow().set(); image.unlockFocus(); cache[key] = image; return image
    }
}
