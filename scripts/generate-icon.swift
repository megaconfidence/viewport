#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

// Renders the Viewport app icon. The foreground glyph mirrors the menu bar:
// the SF Symbol `aspectratio`, drawn in white on an indigo→violet squircle.

_ = NSApplication.shared

let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "Resources/AppIcon.icns"

let colorSpace = CGColorSpaceCreateDeviceRGB()
let backgroundColor = CGColor(srgbRed: 250.0 / 255.0, green: 52.0 / 255.0, blue: 84.0 / 255.0, alpha: 1.0)

func tintedSymbol(_ symbol: NSImage, with color: NSColor) -> NSImage {
    NSImage(size: symbol.size, flipped: false) { rect in
        symbol.draw(in: rect)
        color.setFill()
        rect.fill(using: .sourceIn)
        return true
    }
}

func renderIcon(pixelSize: Int) -> Data {
    let size = CGFloat(pixelSize)
    guard let context = CGContext(
        data: nil,
        width: pixelSize,
        height: pixelSize,
        bitsPerComponent: 8,
        bytesPerRow: pixelSize * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        fatalError("Could not create CGContext at size \(pixelSize)")
    }

    let squircleRadius = size * 0.222
    let squirclePath = CGPath(
        roundedRect: CGRect(x: 0, y: 0, width: size, height: size),
        cornerWidth: squircleRadius,
        cornerHeight: squircleRadius,
        transform: nil
    )

    context.saveGState()
    context.addPath(squirclePath)
    context.clip()
    context.setFillColor(backgroundColor)
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
    context.restoreGState()

    if let baseSymbol = NSImage(systemSymbolName: "aspectratio", accessibilityDescription: nil) {
        let symbolPointSize = size * 0.52
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: symbolPointSize, weight: .medium)
        let configuredSymbol = baseSymbol.withSymbolConfiguration(symbolConfig) ?? baseSymbol
        let whiteSymbol = tintedSymbol(configuredSymbol, with: .white)

        let symbolSize = whiteSymbol.size
        let symbolRect = NSRect(
            x: (size - symbolSize.width) / 2,
            y: (size - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        )

        let nsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = nsContext

        let shadow = NSShadow()
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.006)
        shadow.shadowBlurRadius = size * 0.020
        shadow.shadowColor = NSColor(deviceRed: 0.32, green: 0.04, blue: 0.10, alpha: 0.40)
        shadow.set()

        whiteSymbol.draw(
            in: symbolRect,
            from: .zero,
            operation: .sourceOver,
            fraction: 1.0
        )

        NSGraphicsContext.restoreGraphicsState()
    } else {
        FileHandle.standardError.write(Data("Warning: SF Symbol 'aspectratio' unavailable\n".utf8))
    }

    guard let image = context.makeImage() else {
        fatalError("Could not finalize CGImage at size \(pixelSize)")
    }
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: pixelSize, height: pixelSize)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("Could not encode PNG at size \(pixelSize)")
    }
    return data
}

let variants: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let fileManager = FileManager.default
let iconsetURL = fileManager.temporaryDirectory
    .appendingPathComponent("Viewport-\(UUID().uuidString).iconset", isDirectory: true)

try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

for variant in variants {
    let data = renderIcon(pixelSize: variant.pixels)
    try data.write(to: iconsetURL.appendingPathComponent(variant.name))
}

let outputURL = URL(fileURLWithPath: outputPath)
try? fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", "-o", outputURL.path, iconsetURL.path]

try iconutil.run()
iconutil.waitUntilExit()

try? fileManager.removeItem(at: iconsetURL)

if iconutil.terminationStatus != 0 {
    FileHandle.standardError.write(Data("iconutil failed with status \(iconutil.terminationStatus)\n".utf8))
    exit(1)
}

print("Wrote \(outputURL.path)")
