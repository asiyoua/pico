// Draws the menu bar template icon: a rounded lightning bolt for Pico.
// Run: swift Scripts/make-menubar-icon.swift
// Exports MenuBarIcon-16/32/64.png (black + alpha; rendered as template).

import AppKit

func boltPath(in size: CGFloat) -> NSBezierPath {
    let s = size / 64.0
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 38 * s, y: 4 * s))
    path.line(to: NSPoint(x: 14 * s, y: 36 * s))
    path.line(to: NSPoint(x: 28 * s, y: 36 * s))
    path.line(to: NSPoint(x: 24 * s, y: 60 * s))
    path.line(to: NSPoint(x: 50 * s, y: 26 * s))
    path.line(to: NSPoint(x: 34 * s, y: 26 * s))
    path.close()
    path.lineJoinStyle = .round
    return path
}

func export(_ size: Int) {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    NSColor.black.setFill()
    let path = boltPath(in: CGFloat(size))
    path.fill()
    path.lineWidth = CGFloat(size) / 10.0
    path.stroke()
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError() }
    try! png.write(to: URL(fileURLWithPath: "Resources/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon-\(size).png"))
    print("wrote MenuBarIcon-\(size).png")
}

export(16)
export(32)
export(64)
