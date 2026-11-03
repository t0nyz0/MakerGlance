import AppKit

enum AppGlyph {
    @MainActor static let applicationIcon: NSImage = {
        if let url = Bundle.main.url(forResource: "MakerGlance", withExtension: "icns"), let image = NSImage(contentsOf: url) { return image }
        return NSImage(systemSymbolName: "cube", accessibilityDescription: "MakerGlance")!
    }()
    @MainActor static var menu: NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 20), flipped: false) { _ in
            NSColor.labelColor.setStroke()
            let transform = NSAffineTransform(); transform.scale(by: 0.85); transform.concat()
            for (x,top) in [(3.0,14.0),(9.0,10.0),(15.0,6.0)] {
                let path = NSBezierPath()
                func p(_ x: Double,_ y: Double) -> NSPoint { NSPoint(x:x,y:24-y) }
                path.move(to:p(x,top)); path.line(to:p(x+3,top-1.5)); path.line(to:p(x+6,top)); path.line(to:p(x+6,19.5)); path.line(to:p(x+3,21)); path.line(to:p(x,19.5)); path.close()
                path.move(to:p(x,top)); path.line(to:p(x+3,top+1.5)); path.line(to:p(x+6,top)); path.move(to:p(x+3,top+1.5)); path.line(to:p(x+3,21))
                path.lineWidth = 1.3; path.lineJoinStyle = .round; path.lineCapStyle = .round; path.stroke()
            }
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "3D model growth analytics"; return image
    }
}
