import AppKit

let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
let gc = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = gc
let cg = gc.cgContext

// top-left coordinate helpers
func R(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> CGRect { CGRect(x: x, y: S - y - h, width: w, height: h) }
func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: S - y) }
func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: a)
}
func gradient(_ stops: [(CGFloat, NSColor)]) -> NSGradient {
    NSGradient(colors: stops.map { $0.1 }, atLocations: stops.map { $0.0 }, colorSpace: .sRGB)!
}

let px: CGFloat = 190, pw: CGFloat = 644
let pTop: CGFloat = 100, pBottom: CGFloat = 925
let rollH: CGFloat = 92

// paper body with drop shadow
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -16), blur: 34, color: NSColor.black.withAlphaComponent(0.38).cgColor)
let body = NSBezierPath(roundedRect: R(px, pTop + rollH * 0.5, pw, pBottom - pTop - rollH * 0.5), xRadius: 14, yRadius: 14)
color(0xFBFAF5).setFill()
body.fill()
cg.restoreGState()

// paper tone
cg.saveGState()
body.addClip()
gradient([(0, color(0xFFFFFF)), (1, color(0xEFEDE4))]).draw(in: R(px, pTop, pw, pBottom - pTop), angle: -90)
// shadow cast by the curl onto the paper
gradient([(0, color(0x000000, 0.30)), (0.35, color(0x000000, 0.10)), (1, color(0x000000, 0))])
    .draw(in: R(px, pTop + rollH - 10, pw, 120), angle: -90)
cg.restoreGState()

// the curl: top edge rolled toward the viewer
let roll = NSBezierPath(roundedRect: R(px - 6, pTop, pw + 12, rollH), xRadius: rollH / 2, yRadius: rollH / 2)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -8), blur: 14, color: NSColor.black.withAlphaComponent(0.35).cgColor)
color(0xE4E0D4).setFill()
roll.fill()
cg.restoreGState()
cg.saveGState()
roll.addClip()
gradient([(0, color(0xA9A493)), (0.18, color(0xD3CFC1)), (0.40, color(0xFFFFFF)), (0.65, color(0xE9E6DB)), (1, color(0xB4AF9F))])
    .draw(in: R(px - 6, pTop, pw + 12, rollH), angle: -90)
cg.restoreGState()

// open ends of the roll, a spiral showing the curl
for side in [0, 1] {
    let cx = side == 0 ? px + 8 : px + pw - 8
    let end = NSBezierPath(ovalIn: R(cx - 24, pTop + 4, 48, rollH - 8))
    color(0xC9C4B4).setFill()
    end.fill()
    color(0x8F8A79, 0.9).setStroke()
    end.lineWidth = 3
    end.stroke()
    let inner = NSBezierPath(ovalIn: R(cx - 13, pTop + 22, 26, rollH - 44))
    color(0xE8E5DA).setFill()
    inner.fill()
    color(0x8F8A79, 0.8).setStroke()
    inner.lineWidth = 2.5
    inner.stroke()
}

// logo tile (WOZ LED)
let ts: CGFloat = 470
let tx = (S - ts) / 2, ty: CGFloat = 345
func U(_ u: CGFloat, _ v: CGFloat) -> CGPoint { P(tx + u * ts, ty + v * ts) }
let tile = NSBezierPath(roundedRect: R(tx, ty, ts, ts), xRadius: 6, yRadius: 6)
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -4), blur: 10, color: NSColor.black.withAlphaComponent(0.3).cgColor)
NSColor.black.setFill()
tile.fill()
cg.restoreGState()
cg.saveGState()
tile.addClip()

func poly(_ pts: [(CGFloat, CGFloat)], _ c: NSColor) {
    let p = NSBezierPath()
    p.move(to: U(pts[0].0, pts[0].1))
    for q in pts.dropFirst() { p.line(to: U(q.0, q.1)) }
    p.close()
    c.setFill()
    p.fill()
}
// beam of light from the top
poly([(0.32, 0), (0.67, 0), (0.60, 0.72), (0.39, 0.72)], .white)
// chevron slab underneath
poly([(0.295, 0.78), (0.497, 0.90), (0.699, 0.78), (0.699, 0.835), (0.497, 0.965), (0.295, 0.835)], .white)
// black diamond where the beam lands, white diamond inside
poly([(0.497, 0.645), (0.622, 0.775), (0.497, 0.905), (0.372, 0.775)], .black)
poly([(0.497, 0.71), (0.597, 0.775), (0.497, 0.84), (0.397, 0.775)], .white)
cg.restoreGState()

// gray letters, drawn after so they sit over beam and background
func word(_ s: String, u0: CGFloat, u1: CGFloat, v0: CGFloat, v1: CGFloat) {
    let font = NSFont(name: "Helvetica-Bold", size: 200) ?? NSFont.boldSystemFont(ofSize: 200)
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color(0x8A8A8A)]
    let path = CGMutablePath()
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    for run in runs {
        let f = unsafeBitCast(CFDictionaryGetValue(CTRunGetAttributes(run), Unmanaged.passUnretained(kCTFontAttributeName).toOpaque()), to: CTFont.self)
        var glyphs = [CGGlyph](repeating: 0, count: CTRunGetGlyphCount(run))
        var pos = [CGPoint](repeating: .zero, count: glyphs.count)
        CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: 0), &pos)
        for i in 0..<glyphs.count {
            if let g = CTFontCreatePathForGlyph(f, glyphs[i], nil) {
                path.addPath(g, transform: CGAffineTransform(translationX: pos[i].x, y: pos[i].y))
            }
        }
    }
    let b = path.boundingBoxOfPath
    let target = R(tx + u0 * ts, ty + v0 * ts, (u1 - u0) * ts, (v1 - v0) * ts)
    var t = CGAffineTransform(translationX: -b.minX, y: -b.minY)
    t = t.scaledBy(x: target.width / b.width, y: target.height / b.height)
    t = t.concatenating(CGAffineTransform(translationX: target.minX, y: target.minY))
    // scaledBy applied before translation, so redo in the right order
    var m = CGAffineTransform.identity
    m = m.translatedBy(x: target.minX, y: target.minY)
    m = m.scaledBy(x: target.width / b.width, y: target.height / b.height)
    m = m.translatedBy(x: -b.minX, y: -b.minY)
    cg.saveGState()
    cg.addPath(path.copy(using: &m)!)
    cg.setFillColor(color(0x8A8A8A).cgColor)
    cg.fillPath()
    cg.restoreGState()
}
cg.saveGState()
tile.addClip()
word("WOZ", u0: 0.11, u1: 0.89, v0: 0.09, v1: 0.31)
word("LED", u0: 0.11, u1: 0.89, v0: 0.37, v1: 0.60)
cg.restoreGState()

let data = rep.representation(using: .png, properties: [:])!
try! data.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
