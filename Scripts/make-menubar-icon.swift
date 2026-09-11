// Draws the menu bar template icon: a rounded lightning bolt for Pico.
// Run: swift Scripts/make-menubar-icon.swift
// Exports MenuBarIcon-16/32/64.png (black + alpha; rendered as template).

import AppKit

func boltPath(in size: CGFloat) -> NSBezierPath {
    // The bolt occupies ~66% of the canvas so its optical size matches
    // standard menu bar glyphs (Wi-Fi, battery, etc.).
    let points = [(38.0, 4.0), (14.0, 36.0), (28.0, 36.0), (24.0, 60.0), (50.0, 26.0), (34.0, 26.0)]
    let scale = size / 64.0 * 0.66
    let center = size / 2
    let path = NSBezierPath()
    let vertices = points.map { NSPoint(x: center + ($0.0 - 32) * scale, y: center + ($0.1 - 32) * scale) }
    path.move(to: vertices[0])
    vertices.dropFirst().forEach { path.line(to: $0) }
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
    path.lineWidth = CGFloat(size) / 16.0
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
