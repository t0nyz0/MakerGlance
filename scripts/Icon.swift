import AppKit

let target = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = target.deletingLastPathComponent()
try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}
func polygon(_ points: [NSPoint], _ fill: NSColor) {
    let path = NSBezierPath(); path.move(to: points[0]); for p in points.dropFirst() { path.line(to: p) }; path.close(); fill.setFill(); path.fill()
}
func bitmap(width: Int, height: Int, draw: () -> Void) -> NSBitmapImageRep {
    let result = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: result)
    NSGraphicsContext.current?.imageInterpolation = .high
    draw(); NSGraphicsContext.restoreGraphicsState(); return result
}
func save(_ image: NSBitmapImageRep, _ name: String) throws { try image.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(name)) }

// One original sculptural mark combines printable voxels and upward activity.
// No lettering, printer-control glyphs or dependency on the pending app name.
let art = bitmap(width: 1024, height: 1024) {
    let tile = NSBezierPath(roundedRect: NSRect(x: 96, y: 96, width: 832, height: 832), xRadius: 184, yRadius: 184)
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.35); shadow.shadowBlurRadius = 25; shadow.shadowOffset = NSSize(width: 0, height: -13); shadow.set()
    NSGradient(starting: rgb(0x303135), ending: rgb(0x151618))!.draw(in: tile, angle: -90)
    NSShadow().set(); rgb(0xB8AF83, alpha: 0.2).setStroke(); tile.lineWidth = 2; tile.stroke()
    let colors: [(UInt32,UInt32,UInt32)] = [(0xFFF0B0,0xE6C64D,0xA98722),(0xF7DD7D,0xD8B43B,0x97721B),(0xEFD364,0xCBA52C,0x805D0A)]
    for (index, height) in [150.0,260.0,370.0].enumerated() {
        let x = 234.0 + Double(index) * 174, base = 330.0, top = base + height
        let (cap,left,right) = colors[index]
        polygon([NSPoint(x:x,y:top),NSPoint(x:x+104,y:top-50),NSPoint(x:x+104,y:base-50),NSPoint(x:x,y:base)],rgb(left))
        polygon([NSPoint(x:x+104,y:top-50),NSPoint(x:x+208,y:top),NSPoint(x:x+208,y:base),NSPoint(x:x+104,y:base-50)],rgb(right))
        polygon([NSPoint(x:x,y:top),NSPoint(x:x+104,y:top+50),NSPoint(x:x+208,y:top),NSPoint(x:x+104,y:top-50)],rgb(cap))
    }
}
if target.pathExtension.lowercased() == "icns" {
    // Modern ICNS representations contain PNG data. Building the container
    // directly avoids spawning iconutil's sandboxed image-conversion helper.
    func length(_ value: Int) -> Data {
        var size = UInt32(value).bigEndian
        return withUnsafeBytes(of: &size) { Data($0) }
    }
    let representations: [(String, Int)] = [("icp4",16),("icp5",32),("icp6",64),("ic07",128),
        ("ic08",256),("ic09",512),("ic10",1024),("ic11",32),("ic12",64),("ic13",256),("ic14",512)]
    var chunks = Data()
    for (type, size) in representations {
        let image = bitmap(width: size, height: size) {
            art.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
        }
        let png = image.representation(using: .png, properties: [:])!
        chunks.append(Data(type.utf8)); chunks.append(length(png.count + 8)); chunks.append(png)
    }
    var icon = Data("icns".utf8); icon.append(length(chunks.count + 8)); icon.append(chunks)
    guard let decoded = NSImage(data: icon), !decoded.representations.isEmpty else {
        throw NSError(domain: "MakerGlance.Icon", code: 1, userInfo: [NSLocalizedDescriptionKey: "Generated app icon could not be decoded"])
    }
    try icon.write(to: target)
} else {
    try art.representation(using: .png, properties: [:])!.write(to: target)
}
