import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        NSColor(srgbRed: 0.13, green: 0.33, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 205, yRadius: 205).fill()
        NSColor(srgbRed: 0.87, green: 0.94, blue: 0.90, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 250, y: 190, width: 524, height: 654), xRadius: 78, yRadius: 78).fill()
        NSColor(srgbRed: 0.72, green: 0.83, blue: 0.77, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 250, y: 190, width: 524, height: 142), xRadius: 65, yRadius: 65).fill()
        NSColor(srgbRed: 0.13, green: 0.33, blue: 0.28, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 420, y: 241, width: 184, height: 30), xRadius: 15, yRadius: 15).fill()
        NSBezierPath(ovalIn: NSRect(x: 660, y: 248, width: 18, height: 18)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let filename = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    }
}
