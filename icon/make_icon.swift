import AppKit

// Builds a 1024 icon from icon/favicon-source.png (the woz.lol favicon) in the standard Mac icon shape.
let args = CommandLine.arguments
let src = NSImage(contentsOfFile: args[1])!
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let box = NSRect(x: 100, y: 100, width: 824, height: 824)
NSGraphicsContext.current!.cgContext.setShadow(offset: CGSize(width: 0, height: -10), blur: 24,
                                               color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185).fill()
NSGraphicsContext.current!.cgContext.setShadow(offset: .zero, blur: 0, color: nil)
NSBezierPath(roundedRect: box, xRadius: 185, yRadius: 185).addClip()
NSGraphicsContext.current!.imageInterpolation = .high
src.draw(in: box)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[2]))
