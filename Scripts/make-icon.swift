// Generates the app icon set for the 「闪译」 brand.
// Run: swift Scripts/make-icon.swift
// Draws a macOS-style squircle with an indigo-to-sky gradient, a white
// speech bubble containing 译, and a yellow lightning badge (闪).

import AppKit

let masterSize: CGFloat = 1024
let contentRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 186

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha)
}

func drawMaster() -> NSImage {
    let image = NSImage(size: NSSize(width: masterSize, height: masterSize))
    image.lockFocusFlipped(false)
    guard let context = NSGraphicsContext.current?.cgContext else { fatalError() }

    // Squircle backdrop with a diagonal indigo -> sky gradient.
    let squircle = NSBezierPath(roundedRect: contentRect, xRadius: cornerRadius, yRadius: cornerRadius)
    context.saveGState()
    squircle.addClip()
    let gradient = NSGradient(
        colors: [color(0x4F46E5), color(0x3B6FF0), color(0x21A6F2)])!
    gradient.draw(in: contentRect, angle: -55)
    // Soft top glow for depth (full-width so no banding edge shows).
    let glow = NSGradient(colors: [color(0xFFFFFF, 0.20), color(0xFFFFFF, 0)])!
    glow.draw(in: contentRect, angle: -90)
    context.restoreGState()

    // Subtle edge stroke.
    let edge = NSBezierPath(roundedRect: contentRect.insetBy(dx: 6, dy: 6), xRadius: cornerRadius - 6, yRadius: cornerRadius - 6)
    color(0xFFFFFF, 0.16).setStroke()
    edge.lineWidth = 6
    edge.stroke()

    // Main speech bubble: rounded rectangle with a tail at the bottom-left.
    let bubbleRect = NSRect(x: 212, y: 366, width: 600, height: 440)
    let bubble = NSBezierPath(roundedRect: bubbleRect, xRadius: 88, yRadius: 88)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: bubbleRect.minX + 90, y: bubbleRect.minY + 30))
    tail.line(to: NSPoint(x: bubbleRect.minX + 150, y: bubbleRect.minY - 118))
    tail.line(to: NSPoint(x: bubbleRect.minX + 296, y: bubbleRect.minY - 6))
    tail.close()
    bubble.append(tail)

    let shadow = NSShadow()
    shadow.shadowColor = color(0x0B1030, 0.35)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    context.saveGState()
    shadow.set()
    color(0xFFFFFF).setFill()
    bubble.fill()
    context.restoreGState()

    // 译 glyph centered in the bubble, deep indigo.
    let glyph = NSMutableAttributedString(
        string: "译",
        attributes: [
            .font: NSFont(name: "PingFangSC-Semibold", size: 320) ?? NSFont.boldSystemFont(ofSize: 320),
            .foregroundColor: color(0x3730A3),
        ])
    let glyphSize = glyph.size()
    glyph.draw(
        at: NSPoint(
            x: bubbleRect.midX - glyphSize.width / 2,
            y: bubbleRect.midY - glyphSize.height / 2 - 30))

    // Lightning badge (闪) at the bubble's top-right.
    let badgeRect = NSRect(x: 672, y: 608, width: 178, height: 178)
    let badge = NSBezierPath(roundedRect: badgeRect, xRadius: 48, yRadius: 48)
    let badgeShadow = NSShadow()
    badgeShadow.shadowColor = color(0x0B1030, 0.30)
    badgeShadow.shadowBlurRadius = 16
    badgeShadow.shadowOffset = NSSize(width: 0, height: -8)
    context.saveGState()
    badgeShadow.set()
    let badgeGradient = NSGradient(colors: [color(0xFBBF24), color(0xF59E0B)])!
    badgeGradient.draw(in: badgeRect, angle: -70)
    context.restoreGState()

    // Bolt path inside the badge.
    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: badgeRect.midX + 24, y: badgeRect.maxY - 32))
    bolt.line(to: NSPoint(x: badgeRect.minX + 50, y: badgeRect.midY + 12))
    bolt.line(to: NSPoint(x: badgeRect.midX - 8, y: badgeRect.midY + 8))
    bolt.line(to: NSPoint(x: badgeRect.minX + 20, y: badgeRect.minY + 30))
    bolt.line(to: NSPoint(x: badgeRect.maxX - 48, y: badgeRect.midY - 8))
    bolt.line(to: NSPoint(x: badgeRect.midX + 6, y: badgeRect.midY - 4))
    bolt.close()
    color(0xFFFFFF).setFill()
    bolt.fill()

    image.unlockFocus()
    return image
}

let master = drawMaster()
let masterRep = NSBitmapImageRep(data: master.tiffRepresentation!)!
let cg = masterRep.cgImage!

func export(_ size: CGFloat, _ file: String) {
    let out = NSImage(size: NSSize(width: size, height: size))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.cgContext.draw(cg, in: NSRect(x: 0, y: 0, width: size, height: size))
    out.unlockFocus()
    let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode") }
    let url = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset/\(file)")
    try! png.write(to: url)
    print("wrote \(file)")
}

export(1024, "AppIcon-1024.png")
export(512, "AppIcon-512.png")
export(256, "AppIcon-256.png")
export(128, "AppIcon-128.png")
export(32, "AppIcon-32.png")
export(16, "AppIcon-16.png")
