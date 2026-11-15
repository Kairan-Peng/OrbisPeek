#!/usr/bin/env swift
import AppKit

// Export the checked-in brand masters to the sizes required by the asset catalog.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let manager = FileManager.default
let brand = root.appendingPathComponent("docs/brand")
let catalog = root.appendingPathComponent("App/Assets.xcassets")

func writeJSON(_ value: [String: Any], to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
    try data.write(to: url)
}

func load(_ url: URL) throws -> NSImage {
    guard let image = NSImage(contentsOf: url) else {
        throw CocoaError(.fileReadCorruptFile, userInfo: [NSFilePathErrorKey: url.path])
    }
    return image
}

func export(_ image: NSImage, pixels: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

try manager.createDirectory(at: brand, withIntermediateDirectories: true)
try manager.createDirectory(at: catalog, withIntermediateDirectories: true)

// The generated master has a little transparent padding and edge debris.
// Normalize that export once; the approved symbol and tile artwork stay intact.
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--import-icon" {
    let source = try load(URL(fileURLWithPath: CommandLine.arguments[2]))
    let normalized = NSImage(size: NSSize(width: 1024, height: 1024))
    normalized.lockFocus()
    let tile = NSRect(x: 52, y: 52, width: 920, height: 920)
    NSBezierPath(roundedRect: tile, xRadius: 210, yRadius: 210).addClip()
    NSColor(srgbRed: 245.0 / 255, green: 246.0 / 255, blue: 241.0 / 255, alpha: 1).setFill()
    tile.fill()
    let crop = NSRect(x: source.size.width * 72 / 1254, y: source.size.height * 84 / 1254,
                      width: source.size.width * 1080 / 1254, height: source.size.height * 1080 / 1254)
    source.draw(in: tile, from: crop, operation: .sourceOver, fraction: 1)
    normalized.unlockFocus()
    try export(normalized, pixels: 1024, to: brand.appendingPathComponent("orbispeek-icon.png"))
} else if CommandLine.arguments.count != 1 {
    fatalError("Usage: swift scripts/generate-brand-assets.swift [--import-icon GENERATED_PNG]")
}

let info: [String: Any] = ["author": "xcode", "version": 1]
try writeJSON(["info": info], to: catalog.appendingPathComponent("Contents.json"))

let icon = try load(brand.appendingPathComponent("orbispeek-icon.png"))
let iconSet = catalog.appendingPathComponent("AppIcon.appiconset")
try manager.createDirectory(at: iconSet, withIntermediateDirectories: true)
var iconEntries: [[String: Any]] = []
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let filename = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try export(icon, pixels: size * scale, to: iconSet.appendingPathComponent(filename))
        iconEntries.append(["filename": filename, "idiom": "mac", "scale": "\(scale)x", "size": "\(size)x\(size)"])
    }
}
try writeJSON(["images": iconEntries, "info": info], to: iconSet.appendingPathComponent("Contents.json"))

let mark = try load(brand.appendingPathComponent("orbispeek-mark.png"))
let markSet = catalog.appendingPathComponent("BrandMark.imageset")
try manager.createDirectory(at: markSet, withIntermediateDirectories: true)
var markEntries: [[String: Any]] = []
for scale in [1, 2] {
    let filename = "mark\(scale == 2 ? "@2x" : "").png"
    try export(mark, pixels: 64 * scale, to: markSet.appendingPathComponent(filename))
    markEntries.append(["filename": filename, "idiom": "universal", "scale": "\(scale)x"])
}
try writeJSON(["images": markEntries, "info": info, "properties": ["template-rendering-intent": "template"]],
              to: markSet.appendingPathComponent("Contents.json"))
print("Exported OrbisPeek app icons and brand mark to \(catalog.path)")
