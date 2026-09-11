// Builds the app icon from the 3D "P" logo artwork (pico-logo.png).
// Run: swift Scripts/make-icon-from-logo.swift [path-to-logo.png]
// Renders the 1024px master (logo cover-filled into a macOS squircle), writes
// an .iconset with every required size, then converts it to AppIcon.icns.
// The icns is committed to Resources/ and build-app.sh copies it into the app.

import AppKit

let masterSize: CGFloat = 1024
let contentRect = NSRect(x: 100, y: 100, width: 824, height: 824)
let cornerRadius: CGFloat = 186
let logoPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1] : "pico-logo.png"
let iconsetDir = "/tmp/AppIcon.iconset"

guard let logo = NSImage(contentsOfFile: logoPath) else {
    fatalError("logo not found at \(logoPath)")
}

let image = NSImage(size: NSSize(width: masterSize, height: masterSize))
image.lockFocusFlipped(false)
guard let context = NSGraphicsContext.current?.cgContext else { fatalError() }

// macOS 26 masks full-bleed square art into the system squircle itself, so
// the icon canvas is filled edge to edge — no transparent margins.
let fullRect = NSRect(x: 0, y: 0, width: masterSize, height: masterSize)
logo.draw(
    in: fullRect,
    from: .zero,
    operation: .sourceOver,
    fraction: 1,
    respectFlipped: false,
    hints: [.interpolation: NSImageInterpolation.high.rawValue])

image.unlockFocus()

let masterRep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let cg = masterRep.cgImage!

func renderPNG(_ size: CGFloat) -> Data {
    let out = NSImage(size: NSSize(width: size, height: size))
    out.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.cgContext.draw(cg, in: NSRect(x: 0, y: 0, width: size, height: size))
    out.unlockFocus()
    let rep = NSBitmapImageRep(data: out.tiffRepresentation!)!
    guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode") }
    return png
}

let fileManager = FileManager.default
try? fileManager.removeItem(atPath: iconsetDir)
try! fileManager.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]
for (name, size) in sizes {
    try! renderPNG(size).write(to: URL(fileURLWithPath: "\(iconsetDir)/\(name)"))
    print("wrote \(name)")
}
