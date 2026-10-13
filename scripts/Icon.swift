import AppKit
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let scale = NSAffineTransform(); scale.scale(by: 4); scale.concat()
let shape = NSBezierPath(roundedRect: NSRect(x: 18, y: 18, width: 220, height: 220), xRadius: 52, yRadius: 52)
NSGradient(starting: NSColor(calibratedRed: 0.455, green: 0.471, blue: 1, alpha: 1), ending: NSColor(calibratedRed: 0.263, green: 0.192, blue: 0.659, alpha: 1))!.draw(in: shape, angle: -65)
let mark = NSBezierPath(); mark.lineWidth = 16; mark.lineCapStyle = .round; mark.lineJoinStyle = .round
mark.move(to: NSPoint(x: 64, y: 103)); mark.line(to: NSPoint(x: 64, y: 176)); mark.line(to: NSPoint(x: 128, y: 123)); mark.line(to: NSPoint(x: 192, y: 176)); mark.line(to: NSPoint(x: 192, y: 103))
NSColor.white.setStroke(); mark.stroke()
let drive = NSBezierPath(roundedRect: NSRect(x: 48, y: 47, width: 160, height: 42), xRadius: 14, yRadius: 14)
NSColor.white.withAlphaComponent(0.16).setFill(); drive.fill(); NSColor.white.setStroke(); drive.lineWidth = 5; drive.stroke()
let slot = NSBezierPath(); slot.lineWidth = 6; slot.lineCapStyle = .round; slot.move(to: NSPoint(x: 70, y: 68)); slot.line(to: NSPoint(x: 139, y: 68)); slot.stroke()
NSColor.white.setFill(); NSBezierPath(ovalIn: NSRect(x: 181, y: 64, width: 8, height: 8)).fill()
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
