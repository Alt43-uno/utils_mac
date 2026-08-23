// Renders the application icon as a 1024×1024 PNG.
//
// Run via `swift Scripts/make_icon.swift <output.png>`; the build script then
// downsamples it with `sips` and packs an .icns with `iconutil`.

import AppKit
import CoreGraphics
import Foundation

let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
let side = 1024

guard let context = CGContext(data: nil,
                              width: side,
                              height: side,
                              bitsPerComponent: 8,
                              bytesPerRow: 0,
                              space: CGColorSpace(name: CGColorSpace.sRGB)!,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Could not create the drawing context")
}

let size = CGFloat(side)
let inset = size * 0.085
let squircle = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let radius = squircle.width * 0.235

// Background gradient.
context.saveGState()
let path = CGPath(roundedRect: squircle, cornerWidth: radius, cornerHeight: radius, transform: nil)
context.addPath(path)
context.clip()

let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                          colors: [
                            CGColor(srgbRed: 0.16, green: 0.44, blue: 0.98, alpha: 1),
                            CGColor(srgbRed: 0.45, green: 0.24, blue: 0.92, alpha: 1)
                          ] as CFArray,
                          locations: [0, 1])!
context.drawLinearGradient(gradient,
                           start: CGPoint(x: squircle.minX, y: squircle.maxY),
                           end: CGPoint(x: squircle.maxX, y: squircle.minY),
                           options: [])

// Soft highlight sweeping across the top.
context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
context.fillEllipse(in: CGRect(x: squircle.minX - squircle.width * 0.2,
                               y: squircle.midY,
                               width: squircle.width * 1.4,
                               height: squircle.height * 0.9))
context.restoreGState()

// Stacked "pinned shots" cards.
let cardWidth = size * 0.40
let cardHeight = size * 0.30
let centre = CGPoint(x: size / 2, y: size / 2 - size * 0.01)

func drawCard(offset: CGFloat, alpha: CGFloat, fill: CGColor) {
    let rect = CGRect(x: centre.x - cardWidth / 2 + offset,
                      y: centre.y - cardHeight / 2 - offset,
                      width: cardWidth,
                      height: cardHeight)
    let cardPath = CGPath(roundedRect: rect, cornerWidth: size * 0.035, cornerHeight: size * 0.035, transform: nil)
    context.setShadow(offset: CGSize(width: 0, height: -size * 0.012),
                      blur: size * 0.03,
                      color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
    context.addPath(cardPath)
    context.setFillColor(fill.copy(alpha: alpha)!)
    context.fillPath()
    context.setShadow(offset: .zero, blur: 0, color: nil)
}

drawCard(offset: size * 0.075, alpha: 0.45, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
drawCard(offset: size * 0.037, alpha: 0.75, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
drawCard(offset: 0, alpha: 1, fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))

// Selection brackets over the front card.
let bracket = CGRect(x: centre.x - cardWidth / 2 + size * 0.045,
                     y: centre.y - cardHeight / 2 + size * 0.042,
                     width: cardWidth - size * 0.09,
                     height: cardHeight - size * 0.084)
let armLength = bracket.width * 0.28
let lineWidth = size * 0.026
context.setStrokeColor(CGColor(srgbRed: 0.16, green: 0.40, blue: 0.95, alpha: 1))
context.setLineWidth(lineWidth)
context.setLineCap(.round)

let corners: [(CGPoint, CGPoint, CGPoint)] = [
    (CGPoint(x: bracket.minX, y: bracket.maxY - armLength), CGPoint(x: bracket.minX, y: bracket.maxY), CGPoint(x: bracket.minX + armLength, y: bracket.maxY)),
    (CGPoint(x: bracket.maxX - armLength, y: bracket.maxY), CGPoint(x: bracket.maxX, y: bracket.maxY), CGPoint(x: bracket.maxX, y: bracket.maxY - armLength)),
    (CGPoint(x: bracket.maxX, y: bracket.minY + armLength), CGPoint(x: bracket.maxX, y: bracket.minY), CGPoint(x: bracket.maxX - armLength, y: bracket.minY)),
    (CGPoint(x: bracket.minX + armLength, y: bracket.minY), CGPoint(x: bracket.minX, y: bracket.minY), CGPoint(x: bracket.minX, y: bracket.minY + armLength))
]
for (start, corner, end) in corners {
    context.move(to: start)
    context.addLine(to: corner)
    context.addLine(to: end)
    context.strokePath()
}

guard let image = context.makeImage() else { fatalError("Could not render the icon") }
let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
    fatalError("Could not create \(outputPath)")
}
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write \(outputPath)") }
print("Wrote \(outputPath)")
