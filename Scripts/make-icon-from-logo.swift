// Builds the app icon set from the 3D "P" logo artwork (pico-logo.png).
// Run: swift Scripts/make-icon-from-logo.swift [path-to-logo.png]
// The logo is cover-filled into a macOS squircle so the Dock shows a proper
// rounded shape; a hairline edge keeps the cream square visible on light
// backgrounds.

import AppKit

let masterSize: CGFloat = 1024
let contentRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 186
let logoPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "pico-logo.png"

guard let logo = NSImage(contentsOfFile: logoPath) else {
    fatalError("logo not found at \(logoPath)")
}

let image = NSImage(size: NSSize(width: masterSize, height: masterSize))
image.lockFocusFlipped(false)
guard let context = NSGraphicsContext.current?.cgContext else { fatalError() }

context.clear(NSRect(x: 0, y: 0, width: masterSize, height: masterSize))
let squircle = NSBezierPath(roundedRect: contentRect, xRadius: cornerRadius, yRadius: cornerRadius)
context.saveGState()
squircle.addClip()
// Cover-fill the squircle with the logo artwork (square source, square target).
logo.draw(
    in: contentRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high.rawValue])
context.restoreGState()

// Hairline edge so the cream square keeps definition on light backgrounds.
let edge = NSBezierPath(roundedRect: contentRect.insetBy(dx: 3, dy: 3), xRadius: cornerRadius - 3, yRadius: cornerRadius - 3)
NSColor(white: 0, alpha: 0.08).setStroke()
edge.lineWidth = 5
edge.stroke()

image.unlockFocus()

let masterRep = NSBitmapImageRep(data: image.tiffRepresentation!)!
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
