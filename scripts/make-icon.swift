// 앱 아이콘 생성: swift scripts/make-icon.swift
// main 줄기(흰 선 + 커밋 점)에서 주황 가지가 뻗어 나와 "?" 말풍선으로 끝나는 모양.
import AppKit
import CoreGraphics

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// 1024 기준 좌표(왼쪽 위 원점)로 그린다.
func draw(_ ctx: CGContext) {
    ctx.translateBy(x: 0, y: 1024)
    ctx.scaleBy(x: 1, y: -1)

    // macOS 아이콘 그리드: 824×824 둥근 사각형, 여백 100
    let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
    let platePath = CGPath(roundedRect: plate, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 그림자
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0x000000, 0.35))
    ctx.addPath(platePath)
    ctx.setFillColor(color(0x2A2470))
    ctx.fillPath()
    ctx.restoreGState()

    // 배경 그라데이션 (인디고 → 딥 퍼플)
    ctx.saveGState()
    ctx.addPath(platePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                        colors: [color(0x5C6BFF), color(0x3B2F9E)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 200, y: 100), end: CGPoint(x: 824, y: 924), options: [])
    // 위쪽 은은한 하이라이트
    let shine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                           colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(shine, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
    ctx.restoreGState()

    let mainX: CGFloat = 375
    let dots: [CGFloat] = [255, 512, 769]
    let orange = color(0xFFB547)
    let white = color(0xFFFFFF)

    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)

    // main 줄기
    ctx.setStrokeColor(color(0xFFFFFF, 0.92))
    ctx.setLineWidth(52)
    ctx.move(to: CGPoint(x: mainX, y: dots[0]))
    ctx.addLine(to: CGPoint(x: mainX, y: dots[2]))
    ctx.strokePath()

    // 두 번째(작은) 가지: 아래 커밋에서 반투명 말풍선으로
    let small = CGRect(x: 575, y: 600, width: 190, height: 140)
    // 선과 말풍선을 한 레이어로 그린 뒤 한 번에 반투명 처리 (겹친 부분이 진해지지 않게)
    ctx.saveGState()
    ctx.setAlpha(0.38)
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(white)
    ctx.setLineWidth(40)
    ctx.move(to: CGPoint(x: mainX, y: dots[2]))
    ctx.addCurve(to: CGPoint(x: small.minX + 45, y: small.maxY - 30),
                 control1: CGPoint(x: mainX + 120, y: dots[2]),
                 control2: CGPoint(x: small.minX + 10, y: small.maxY + 5))
    ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: small, cornerWidth: 50, cornerHeight: 50, transform: nil))
    ctx.setFillColor(white)
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()
    ctx.setFillColor(color(0xFFFFFF, 0.85))
    for i in 0..<3 {
        let cx = small.midX + CGFloat(i - 1) * 42
        ctx.fillEllipse(in: CGRect(x: cx - 13, y: small.midY - 13, width: 26, height: 26))
    }

    // 메인 가지: 가운데 커밋에서 뻗어 나와 그대로 말풍선 꼬리가 된다
    let bubble = CGRect(x: 545, y: 235, width: 280, height: 220)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 10), blur: 26, color: color(0x1A1250, 0.45))
    ctx.beginTransparencyLayer(auxiliaryInfo: nil)
    ctx.setStrokeColor(orange)
    ctx.setLineWidth(52)
    ctx.move(to: CGPoint(x: mainX, y: dots[1]))
    ctx.addCurve(to: CGPoint(x: bubble.minX + 70, y: bubble.maxY - 50),
                 control1: CGPoint(x: mainX + 150, y: dots[1]),
                 control2: CGPoint(x: bubble.minX + 20, y: bubble.maxY + 20))
    ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: bubble, cornerWidth: 72, cornerHeight: 72, transform: nil))
    ctx.setFillColor(orange)
    ctx.fillPath()
    ctx.endTransparencyLayer()
    ctx.restoreGState()

    // 커밋 점
    for (i, y) in dots.enumerated() {
        let r: CGFloat = i == 1 ? 52 : 46
        ctx.setFillColor(i == 1 ? orange : white)
        ctx.fillEllipse(in: CGRect(x: mainX - r, y: y - r, width: r * 2, height: r * 2))
        if i == 1 {
            ctx.setFillColor(color(0x3B2F9E))
            ctx.fillEllipse(in: CGRect(x: mainX - 20, y: y - 20, width: 40, height: 40))
        }
    }

    // "?" 글자
    let font = NSFont.systemFont(ofSize: 170, weight: .heavy)
    let attr = NSAttributedString(string: "?", attributes: [
        .font: font, .foregroundColor: NSColor(cgColor: color(0x2A2470))!,
    ])
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.saveGState()
    ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
    ctx.textPosition = CGPoint(x: bubble.midX - bounds.midX, y: bubble.midY + bounds.midY)
    CTLineDraw(line, ctx)
    ctx.restoreGState()
}

func render(size: Int) -> Data {
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
    draw(ctx)
    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base).write(to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2).write(to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024).write(to: root.appendingPathComponent("Resources/icon.png"))
print("✅ iconset + Resources/icon.png")
