// Рисует иконку Overtext: swift Assets/make-icon.swift Assets/
import AppKit

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."

func draw(_ px: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(px) / 1024
    ctx.scaleBy(x: s, y: s)

    // плитка по сетке macOS
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
    ctx.addPath(tilePath); ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [
        NSColor(red: 0.07, green: 0.30, blue: 0.42, alpha: 1).cgColor,
        NSColor(red: 0.03, green: 0.06, blue: 0.10, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])

    func card(center: CGPoint, angle: CGFloat, fill: NSColor, line: NSColor, letter: String, letterColor: NSColor) {
        ctx.saveGState()
        ctx.translateBy(x: center.x, y: center.y)
        ctx.rotate(by: angle * .pi / 180)
        let r = CGRect(x: -250, y: -175, width: 500, height: 350)
        ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: 52, cornerHeight: 52, transform: nil))
        ctx.setFillColor(fill.cgColor); ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        // буква
        let font = NSFont.systemFont(ofSize: 210, weight: .heavy)
        let str = NSAttributedString(string: letter, attributes: [.font: font, .foregroundColor: letterColor])
        let size = str.size()
        NSGraphicsContext.saveGraphicsState()
        str.draw(at: CGPoint(x: -205, y: -size.height / 2 + 4))
        NSGraphicsContext.restoreGraphicsState()
        // строки текста
        for (i, w) in [190.0, 230.0, 150.0].enumerated() {
            let lr = CGRect(x: 5, y: 62 - CGFloat(i) * 70, width: CGFloat(w), height: 30)
            ctx.addPath(CGPath(roundedRect: lr, cornerWidth: 15, cornerHeight: 15, transform: nil))
        }
        ctx.setFillColor(line.cgColor); ctx.fillPath()
        ctx.restoreGState()
    }

    // оригинал снизу, перевод ложится поверх
    card(center: CGPoint(x: 470, y: 620), angle: 7,
         fill: NSColor(red: 0.20, green: 0.27, blue: 0.33, alpha: 1),
         line: NSColor(white: 1, alpha: 0.22), letter: "A", letterColor: NSColor(white: 1, alpha: 0.55))
    card(center: CGPoint(x: 548, y: 400), angle: -5,
         fill: NSColor(white: 0.98, alpha: 1),
         line: NSColor(red: 0.07, green: 0.30, blue: 0.42, alpha: 0.35), letter: "Я",
         letterColor: NSColor(red: 0.02, green: 0.55, blue: 0.75, alpha: 1))
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let set = URL(fileURLWithPath: out).appendingPathComponent("AppIcon.iconset")
try? FileManager.default.createDirectory(at: set, withIntermediateDirectories: true)
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! draw(px).representation(using: .png, properties: [:])!.write(to: set.appendingPathComponent("icon_\(name).png"))
}
try! draw(1024).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out).appendingPathComponent("icon-1024.png"))
print("готово")
