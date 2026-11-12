// Turns raw simulator screenshots into App Store marketing images: a headline and subtitle over the brand
// gradient, with the screenshot in a rounded device-style frame below.
//
// Usage: swift scripts/compose-screenshots.swift <raw-folder> <captions.json> <out-folder>
//   captions.json: [{ "shot": "01_answer", "title": "Two\nlines", "subtitle": "One line" }, …] in App Store order.
// Output: <out-folder>/NN_shot.png at the raw screenshots' own size (1320×2868 from an iPhone Pro Max, which
// App Store Connect accepts for the 6.9" slot and scales down for smaller iPhones).
import AppKit
import CoreGraphics

struct Caption: Decodable { let shot: String; let title: String; let subtitle: String }

let args = CommandLine.arguments
guard args.count == 4 else { fatalError("usage: compose-screenshots.swift <raw-folder> <captions.json> <out-folder>") }
let raw = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[3])
let captions = try JSONDecoder().decode([Caption].self, from: Data(contentsOf: URL(fileURLWithPath: args[2])))
try? FileManager.default.removeItem(at: out)
try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: size) } ?? base
}

for (i, caption) in captions.enumerated() {
    let source = raw.appendingPathComponent(caption.shot + ".png")
    guard let image = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        fatalError("Missing screenshot \(source.path). Captions and UITests/ScreenshotTests.swift must agree.")
    }
    let w = CGFloat(image.width), h = CGFloat(image.height), u = w / 1320  // u: layout unit
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

    let gradient = CGGradient(colorsSpace: space, colors: [rgb(0x0B4A42), rgb(0x13786A), rgb(0x3FAE9A)] as CFArray,
                              locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

    // Headline and subtitle (AppKit text, drawn into the same context).
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    let center = NSMutableParagraphStyle()
    center.alignment = .center
    center.lineHeightMultiple = 0.95
    let title = NSAttributedString(string: caption.title, attributes: [
        .font: rounded(112 * u, .heavy), .foregroundColor: NSColor.white, .paragraphStyle: center])
    let subtitle = NSAttributedString(string: caption.subtitle, attributes: [
        .font: rounded(50 * u, .medium), .foregroundColor: NSColor.white.withAlphaComponent(0.88), .paragraphStyle: center])
    let textWidth = w - 120 * u
    let titleHeight = title.boundingRect(with: CGSize(width: textWidth, height: .infinity), options: .usesLineFragmentOrigin).height
    let subtitleHeight = subtitle.boundingRect(with: CGSize(width: textWidth, height: .infinity), options: .usesLineFragmentOrigin).height
    let headerHeight = 640 * u
    let block = titleHeight + 24 * u + subtitleHeight
    let top = h - 120 * u - max(0, (headerHeight - 120 * u - block) / 2)
    title.draw(with: CGRect(x: 60 * u, y: top - titleHeight, width: textWidth, height: titleHeight), options: .usesLineFragmentOrigin)
    subtitle.draw(with: CGRect(x: 60 * u, y: top - block, width: textWidth, height: subtitleHeight), options: .usesLineFragmentOrigin)

    // The screenshot in a device-style frame, running off the bottom edge.
    let deviceWidth = w - 200 * u
    let deviceHeight = deviceWidth * h / w
    let frame = CGRect(x: 100 * u, y: h - headerHeight - deviceHeight, width: deviceWidth, height: deviceHeight)
    let radius = 96 * u, bezel = 16 * u
    let outer = CGPath(roundedRect: frame.insetBy(dx: -bezel, dy: -bezel), cornerWidth: radius + bezel,
                       cornerHeight: radius + bezel, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -24 * u), blur: 70 * u, color: rgb(0x000000, 0.35))
    ctx.setFillColor(rgb(0x0D1512))
    ctx.addPath(outer)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.interpolationQuality = .high
    ctx.draw(image, in: frame)
    ctx.restoreGState()

    let name = String(format: "%02d_%@.png", i + 1, String(caption.shot.drop(while: { $0.isNumber || $0 == "_" })))
    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    try rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("Composed \(name)")
}
