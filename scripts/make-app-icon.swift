// Draws the BackcountryAI app icon (1024×1024, opaque, no alpha, as App Store Connect requires) in the app's
// Theme colors: a low sun over two mountain ridges, with a speech-bubble moon for Scout.
//
// Usage: swift scripts/make-app-icon.swift [out.png]
//   default: Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png
// Replace the PNG with a designed icon whenever you like; nothing else depends on this script.
import AppKit
import CoreGraphics

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1]
    : "Sources/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let size = 1024
let s = CGFloat(size)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

// Sky: dusk teal at the top to warm light at the horizon.
let sky = CGGradient(colorsSpace: space, colors: [rgb(0x0E5F55), rgb(0x3FAE9A), rgb(0xF2D27A)] as CFArray,
                     locations: [0, 0.62, 1])!
ctx.drawLinearGradient(sky, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s * 0.32), options: [.drawsAfterEndLocation])

// Sun, low between the peaks.
ctx.setFillColor(rgb(0xFFE7A3))
ctx.fillEllipse(in: CGRect(x: s * 0.36, y: s * 0.38, width: s * 0.28, height: s * 0.28))

// Scout's speech bubble, up in the sky like a moon.
ctx.setFillColor(rgb(0xFFFFFF, 0.95))
let bubble = CGRect(x: s * 0.6, y: s * 0.7, width: s * 0.22, height: s * 0.15)
ctx.addPath(CGPath(roundedRect: bubble, cornerWidth: s * 0.075, cornerHeight: s * 0.075, transform: nil))
ctx.fillPath()
ctx.move(to: CGPoint(x: bubble.minX + s * 0.045, y: bubble.minY + s * 0.01))
ctx.addLine(to: CGPoint(x: bubble.minX + s * 0.01, y: bubble.minY - s * 0.045))
ctx.addLine(to: CGPoint(x: bubble.minX + s * 0.1, y: bubble.minY + s * 0.01))
ctx.fillPath()
ctx.setFillColor(rgb(0x13786A))
for i in 0..<3 {
    let d = s * 0.03
    ctx.fillEllipse(in: CGRect(x: bubble.minX + s * 0.045 + CGFloat(i) * s * 0.05, y: bubble.midY - d / 2, width: d, height: d))
}

func ridge(_ points: [(CGFloat, CGFloat)], _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.move(to: CGPoint(x: 0, y: 0))
    for (x, y) in points { ctx.addLine(to: CGPoint(x: x * s, y: y * s)) }
    ctx.addLine(to: CGPoint(x: s, y: 0))
    ctx.closePath()
    ctx.fillPath()
}

// Back ridge, then the front ridge.
ridge([(0, 0.42), (0.18, 0.56), (0.3, 0.47), (0.52, 0.64), (0.7, 0.5), (0.86, 0.58), (1, 0.46)], rgb(0x4C7A5A))
ridge([(0, 0.3), (0.22, 0.5), (0.36, 0.4), (0.5, 0.28), (0.66, 0.44), (0.8, 0.34), (1, 0.4)], rgb(0x1E4636))
let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
