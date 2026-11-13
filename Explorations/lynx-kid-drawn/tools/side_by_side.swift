import AppKit
let dir = CommandLine.arguments[1], out = CommandLine.arguments[2]
let files = try! FileManager.default.contentsOfDirectory(atPath: dir).sorted()
for f in files where f.contains("_pika_") {
    let l = f.replacingOccurrences(of: "_pika_", with: "_lynx_")
    guard let a = NSImage(contentsOfFile: dir+"/"+f), let b = NSImage(contentsOfFile: dir+"/"+l) else { continue }
    let w = 603.0, h = 1311.0, gap = 24.0, top = 60.0
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(w*2+gap), pixelsHigh: Int(h+top), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor.white.setFill(); NSRect(x: 0, y: 0, width: w*2+gap, height: h+top).fill()
    a.draw(in: NSRect(x: 0, y: 0, width: w, height: h)); b.draw(in: NSRect(x: w+gap, y: 0, width: w, height: h))
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 32, weight: .bold)]
    ("Pika" as NSString).draw(at: NSPoint(x: w/2-35, y: h+12), withAttributes: attrs)
    ("Lynx (kid)" as NSString).draw(at: NSPoint(x: w+gap+w/2-80, y: h+12), withAttributes: attrs)
    NSGraphicsContext.current = nil
    let name = f.replacingOccurrences(of: "_pika", with: "")
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out+"/"+name))
}
