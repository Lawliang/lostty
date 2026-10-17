// Makes LosttyMacBetaIcon.appiconset from LosttyMacIcon.appiconset: each
// image with a band reading "BETA" across the bottom, in Lostty's accent,
// clipped to the icon's own shape. Run again whenever the icon changes:
//   cd macos && swift make-beta-icon.swift
import AppKit

let assets = URL(fileURLWithPath: "Assets.xcassets")
let source = assets.appendingPathComponent("LosttyMacIcon.appiconset")
let target = assets.appendingPathComponent("LosttyMacBetaIcon.appiconset")
let accent = NSColor(srgbRed: 0xE5 / 255.0, green: 0x19 / 255.0, blue: 0x9C / 255.0, alpha: 1)
let files = FileManager.default

try? files.removeItem(at: target)
try files.createDirectory(at: target, withIntermediateDirectories: true)

for name in try files.contentsOfDirectory(atPath: source.path) where name.hasSuffix(".png") {
    guard let image = NSImage(contentsOf: source.appendingPathComponent(name)),
          let pixels = image.representations.first else { fatalError("can't read \(name)") }
    let width = pixels.pixelsWide, height = pixels.pixelsHigh
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("can't draw \(name)") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let size = CGSize(width: width, height: height)
    image.draw(in: CGRect(origin: .zero, size: size))
    // Inside the icon's rounded square only (Apple's grid: 824 of 1024,
    // corner radius 185), so the band neither crosses the corners nor tints
    // the drop shadow around them.
    let body = CGRect(origin: .zero, size: size).insetBy(dx: size.width * 100 / 1024, dy: size.height * 100 / 1024)
    NSBezierPath(roundedRect: body, xRadius: size.width * 185 / 1024, yRadius: size.height * 185 / 1024).addClip()
    let band = CGRect(x: 0, y: size.height * 0.14, width: size.width, height: size.height * 0.17)
    accent.setFill()
    band.fill()
    let font = NSFont.systemFont(ofSize: band.height * 0.62, weight: .heavy)
    let text = NSAttributedString(string: "BETA", attributes: [
        .font: font, .foregroundColor: NSColor.white, .kern: band.height * 0.08,
    ])
    let textSize = text.size()
    text.draw(at: CGPoint(x: (size.width - textSize.width) / 2, y: band.midY - textSize.height / 2))
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("can't encode \(name)") }
    try png.write(to: target.appendingPathComponent(name.replacingOccurrences(of: "LosttyMacIcon", with: "LosttyMacBetaIcon")))
}

let contents = try String(contentsOf: source.appendingPathComponent("Contents.json"), encoding: .utf8)
try contents.replacingOccurrences(of: "LosttyMacIcon", with: "LosttyMacBetaIcon")
    .write(to: target.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
print("Wrote \(target.path)")
