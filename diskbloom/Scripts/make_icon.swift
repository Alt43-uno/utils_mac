import AppKit

let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
let palette: [Int] = [0x6BDDBA, 0xA5DE79, 0xEBD68A, 0xF3AF91, 0xE68DAC, 0xBD96EF, 0x9099F1, 0x75BAF0]
func color(_ hex: Int) -> NSColor { NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1) }
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let size = points * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext; context.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
        color(0x182238).setFill(); NSBezierPath(roundedRect: NSRect(x: 38, y: 38, width: 948, height: 948), xRadius: 207, yRadius: 207).fill()
        let center = CGPoint(x: 512, y: 512)
        for i in 0..<8 {
            for depth in 0..<(3 + i % 3) {
                let a = CGFloat(i) * .pi / 4 + 0.025, b = CGFloat(i + 1) * .pi / 4 - 0.025
                let r0 = CGFloat(100 + depth * 54), r1 = r0 + 48
                let path = CGMutablePath()
                path.move(to: CGPoint(x: center.x + cos(a) * r0, y: center.y + sin(a) * r0))
                path.addLine(to: CGPoint(x: center.x + cos(a) * r1, y: center.y + sin(a) * r1))
                path.addArc(center: center, radius: r1, startAngle: a, endAngle: b, clockwise: false)
                path.addLine(to: CGPoint(x: center.x + cos(b) * r0, y: center.y + sin(b) * r0))
                path.addArc(center: center, radius: r0, startAngle: b, endAngle: a, clockwise: true); path.closeSubpath()
                context.addPath(path); context.setFillColor(color(palette[i]).blended(withFraction: CGFloat(depth) * 0.055, of: .white)!.cgColor); context.fillPath()
            }
        }
        color(0x6BDDBA).setStroke(); let circle = NSBezierPath(ovalIn: NSRect(x: 438, y: 438, width: 148, height: 148)); circle.lineWidth = 4; circle.stroke()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(directory)/icon_\(points)x\(points)\(suffix).png"))
    }
}
