import AppKit

guard CommandLine.arguments.count == 2 else { fatalError("Usage: make_icon.swift output.png") }
let size = NSSize(width: 1024, height: 1024)
let image = NSImage(size: size)
image.lockFocus()
let background = NSBezierPath(roundedRect: NSRect(x: 32, y: 32, width: 960, height: 960), xRadius: 216, yRadius: 216)
NSColor(calibratedRed: 0.14, green: 0.46, blue: 0.45, alpha: 1).setFill(); background.fill()
let body = NSBezierPath(roundedRect: NSRect(x: 290, y: 184, width: 444, height: 656), xRadius: 220, yRadius: 220)
NSColor.white.setFill(); body.fill()
let dividingLine = NSBezierPath(); dividingLine.move(to: NSPoint(x: 304, y: 548)); dividingLine.line(to: NSPoint(x: 720, y: 548))
dividingLine.lineWidth = 8; NSColor(calibratedWhite: 0.85, alpha: 1).setStroke(); dividingLine.stroke()
let wheel = NSBezierPath(roundedRect: NSRect(x: 482, y: 622, width: 60, height: 130), xRadius: 28, yRadius: 28)
NSColor(calibratedRed: 0.14, green: 0.46, blue: 0.45, alpha: 1).setFill(); wheel.fill()
image.unlockFocus()
guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Could not render icon") }
try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
