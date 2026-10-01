import AppKit

let output = CommandLine.arguments[1]
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let rect = NSRect(x: 72, y: 72, width: 880, height: 880)
let rounded = NSBezierPath(roundedRect: rect, xRadius: 200, yRadius: 200)
NSGradient(starting: NSColor(red: 0.06, green: 0.68, blue: 0.59, alpha: 1), ending: NSColor(red: 0.01, green: 0.34, blue: 0.35, alpha: 1))!.draw(in: rounded, angle: -70)
NSColor.white.withAlphaComponent(0.09).setStroke()
for x in stride(from: 250, through: 800, by: 140) {
    let line = NSBezierPath(); line.move(to: NSPoint(x: x, y: 225)); line.line(to: NSPoint(x: x, y: 800)); line.lineWidth = 2; line.stroke()
}
for y in stride(from: 250, through: 800, by: 140) {
    let line = NSBezierPath(); line.move(to: NSPoint(x: 225, y: y)); line.line(to: NSPoint(x: 800, y: y)); line.lineWidth = 2; line.stroke()
}
let pulse = NSBezierPath()
pulse.move(to: NSPoint(x: 248, y: 496))
for point in [NSPoint(x: 368, y: 496), NSPoint(x: 440, y: 674), NSPoint(x: 533, y: 343), NSPoint(x: 613, y: 577), NSPoint(x: 665, y: 496), NSPoint(x: 784, y: 496)] { pulse.line(to: point) }
pulse.lineWidth = 48; pulse.lineCapStyle = .round; pulse.lineJoinStyle = .round
NSColor.white.setStroke(); pulse.stroke()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
