#!/usr/bin/env swift
// Generates turkeng app icon: deep blue-to-teal gradient with "TR ↔ EN" text

import AppKit

let size: CGFloat = 1024

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

guard let context = NSGraphicsContext.current?.cgContext else {
    fatalError("No graphics context")
}

// macOS squircle (continuous corner radius)
let rect = CGRect(x: 0, y: 0, width: size, height: size)
let cornerRadius: CGFloat = size * 0.22
let path = NSBezierPath(roundedRect: rect, xRadius: cornerRadius, yRadius: cornerRadius)
path.addClip()

// Deep blue-to-teal gradient
let colorSpace = CGColorSpaceCreateDeviceRGB()
let colors = [
    CGColor(red: 0.08, green: 0.12, blue: 0.45, alpha: 1.0),  // deep blue
    CGColor(red: 0.05, green: 0.55, blue: 0.55, alpha: 1.0),   // teal
] as CFArray
let gradient = CGGradient(colorsSpace: colorSpace, colors: colors, locations: [0.0, 1.0])!
context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])

// Draw text
let white = NSColor.white

// "TR" on the left
let trAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size * 0.22, weight: .bold),
    .foregroundColor: white,
]
let trString = NSAttributedString(string: "TR", attributes: trAttrs)
let trSize = trString.size()

// "EN" on the right
let enAttrs = trAttrs
let enString = NSAttributedString(string: "EN", attributes: enAttrs)
let enSize = enString.size()

// "↔" arrow in the middle
let arrowAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size * 0.18, weight: .medium),
    .foregroundColor: white.withAlphaComponent(0.85),
]
let arrowString = NSAttributedString(string: "↔", attributes: arrowAttrs)
let arrowSize = arrowString.size()

let spacing: CGFloat = size * 0.04
let totalWidth = trSize.width + spacing + arrowSize.width + spacing + enSize.width
let startX = (size - totalWidth) / 2
let baselineY = (size - trSize.height) / 2

trString.draw(at: NSPoint(x: startX, y: baselineY))
arrowString.draw(at: NSPoint(x: startX + trSize.width + spacing, y: baselineY + (trSize.height - arrowSize.height) / 2))
enString.draw(at: NSPoint(x: startX + trSize.width + spacing + arrowSize.width + spacing, y: baselineY))

image.unlockFocus()

// Save as PNG
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Failed to create PNG")
}

let outputPath = (CommandLine.arguments.count > 1) ? CommandLine.arguments[1] : "icon_1024.png"
let url = URL(fileURLWithPath: outputPath)
try! png.write(to: url)
print("Generated \(outputPath)")
