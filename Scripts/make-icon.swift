// Generates the app icon set for the 「Pico」 brand.
// Run: swift Scripts/make-icon.swift
// Pico is a tiny assistant: a speech-bubble face with big eyes, a smile and
// an antenna, drawn on a macOS-style gradient squircle.

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

    // Antenna: stem + glowing yellow orb, drawn behind the head.
    let antenna = NSBezierPath()
    antenna.move(to: NSPoint(x: 512, y: 774))
    antenna.line(to: NSPoint(x: 512, y: 846))
    color(0x3730A3).setStroke()
    antenna.lineWidth = 22
    antenna.lineCapStyle = .round
    antenna.stroke()
    let orbRect = NSRect(x: 512 - 46, y: 838, width: 92, height: 92)
    let orbShadow = NSShadow()
    orbShadow.shadowColor = color(0xFBBF24, 0.55)
    orbShadow.shadowBlurRadius = 30
    orbShadow.shadowOffset = .zero
    context.saveGState()
    orbShadow.set()
    NSBezierPath(ovalIn: orbRect).addClip()
    let orbGradient = NSGradient(colors: [color(0xFDE68A), color(0xF59E0B)])!
    orbGradient.draw(in: orbRect, angle: -70)
    context.restoreGState()

    // Head: white speech-bubble face with a tail at the bottom-left.
    let headRect = NSRect(x: 224, y: 300, width: 576, height: 470)
    let head = NSBezierPath(roundedRect: headRect, xRadius: 116, yRadius: 116)
    let tail = NSBezierPath()
    tail.move(to: NSPoint(x: headRect.minX + 110, y: headRect.minY + 20))
    tail.line(to: NSPoint(x: headRect.minX + 170, y: headRect.minY - 118))
    tail.line(to: NSPoint(x: headRect.minX + 300, y: headRect.minY - 10))
    tail.close()
    head.append(tail)

    let shadow = NSShadow()
    shadow.shadowColor = color(0x0B1030, 0.35)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    context.saveGState()
    shadow.set()
    color(0xFFFFFF).setFill()
    head.fill()
    context.restoreGState()

    // Eyes: two rounded vertical pills in the upper half of the face.
    let eyeColor = color(0x3730A3)
    for eyeCenterX in [382.0, 642.0] {
        let eye = NSBezierPath(
            roundedRect: NSRect(x: eyeCenterX - 28, y: 548, width: 56, height: 148),
            xRadius: 28, yRadius: 28)
        eyeColor.setFill()
        eye.fill()
    }

    // Smile: a gentle arc below the eyes.
    let smile = NSBezierPath()
    smile.move(to: NSPoint(x: 444, y: 512))
    smile.curve(
        to: NSPoint(x: 580, y: 512),
        controlPoint1: NSPoint(x: 474, y: 452),
        controlPoint2: NSPoint(x: 550, y: 452))
    eyeColor.setStroke()
    smile.lineWidth = 24
    smile.lineCapStyle = .round
    smile.stroke()

    // Blush: soft pink circles on the cheeks.
    color(0xFDA4AF, 0.65).setFill()
    NSBezierPath(ovalIn: NSRect(x: 288, y: 496, width: 66, height: 44)).fill()
    NSBezierPath(ovalIn: NSRect(x: 670, y: 496, width: 66, height: 44)).fill()

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
