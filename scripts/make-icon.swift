import AppKit

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

for size in sizes {
    let s = CGFloat(size)
    let image = NSImage(size: NSSize(width: s, height: s))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded square, deep green gradient.
    let inset = s * 0.06
    let rect = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.225, yRadius: s * 0.225)
    path.addClip()
    let gradient = NSGradient(colors: [NSColor(red: 0.055, green: 0.298, blue: 0.239, alpha: 1),
                                       NSColor(red: 0.129, green: 0.522, blue: 0.400, alpha: 1)])!
    gradient.draw(in: rect, angle: -90)

    // Rising bars + trend line.
    let barColor = NSColor(white: 1, alpha: 0.92)
    let heights: [CGFloat] = [0.16, 0.26, 0.36, 0.50]
    let barWidth = rect.width * 0.11
    let gap = rect.width * 0.055
    let totalWidth = barWidth * CGFloat(heights.count) + gap * CGFloat(heights.count - 1)
    var x = rect.midX - totalWidth / 2
    let baseY = rect.minY + rect.height * 0.20
    for h in heights {
        let bar = NSBezierPath(roundedRect: CGRect(x: x, y: baseY, width: barWidth, height: rect.height * h),
                               xRadius: barWidth * 0.35, yRadius: barWidth * 0.35)
        barColor.setFill()
        bar.fill()
        x += barWidth + gap
    }

    // Trend line rising over the bars, with a small head.
    let accent = NSColor(red: 0.984, green: 0.855, blue: 0.463, alpha: 1)
    let start = CGPoint(x: rect.minX + rect.width * 0.17, y: rect.minY + rect.height * 0.50)
    let end = CGPoint(x: rect.maxX - rect.width * 0.17, y: rect.minY + rect.height * 0.82)
    let line = NSBezierPath()
    line.lineWidth = max(1, s * 0.038)
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    line.move(to: start)
    line.line(to: end)
    accent.setStroke()
    line.stroke()

    let head = NSBezierPath()
    head.lineWidth = line.lineWidth
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: CGPoint(x: end.x - rect.width * 0.14, y: end.y))
    head.line(to: end)
    head.line(to: CGPoint(x: end.x, y: end.y - rect.height * 0.14))
    head.stroke()

    ctx.resetClip()
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { continue }
    try? png.write(to: URL(fileURLWithPath: "\(out)/icon_\(size).png"))
}
print("done")
