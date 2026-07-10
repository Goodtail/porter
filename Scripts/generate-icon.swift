#!/usr/bin/env swift
// Generates the flat Porter app icon (1024x1024 PNG).
// Usage: swift Scripts/generate-icon.swift <output.png>
// Design: Big Sur-style squircle in deep navy, with the app's connected-nodes
// motif (two signal-green nodes + one blue) — flat, no gradients on the glyph.

import AppKit

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
let size = 1024

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

guard let ctx = CGContext(
    data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
    space: CGColorSpace(name: CGColorSpace.sRGB)!,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else { fatalError("no context") }

// Apple icon grid: 824pt rounded square centered on a 1024 canvas.
let plate = CGRect(x: 100, y: 100, width: 824, height: 824)
let platePath = CGPath(roundedRect: plate, cornerWidth: 186, cornerHeight: 186, transform: nil)

ctx.saveGState()
ctx.addPath(platePath)
ctx.clip()
let gradient = CGGradient(
    colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
    colors: [srgb(0x1C232F), srgb(0x0B0E13)] as CFArray,
    locations: [0, 1]
)!
ctx.drawLinearGradient(gradient,
                       start: CGPoint(x: 512, y: plate.maxY),
                       end: CGPoint(x: 512, y: plate.minY),
                       options: [])
ctx.restoreGState()

// Hairline plate edge for definition on white backgrounds.
ctx.addPath(platePath)
ctx.setStrokeColor(srgb(0x2A3242, 0.9))
ctx.setLineWidth(6)
ctx.strokePath()

// Connected-nodes glyph.
let nodeA = CGPoint(x: 356, y: 596)  // green
let nodeB = CGPoint(x: 672, y: 646)  // blue
let nodeC = CGPoint(x: 512, y: 338)  // green

ctx.setStrokeColor(srgb(0x3D4A66))
ctx.setLineWidth(30)
ctx.setLineCap(.round)
for (from, to) in [(nodeA, nodeB), (nodeB, nodeC), (nodeC, nodeA)] {
    ctx.move(to: from)
    ctx.addLine(to: to)
    ctx.strokePath()
}

func dot(_ center: CGPoint, radius: CGFloat, color: CGColor) {
    // Dark ring so dots read as "plugged-in ports" against the lines.
    ctx.setFillColor(srgb(0x0B0E13))
    ctx.fillEllipse(in: CGRect(x: center.x - radius - 22, y: center.y - radius - 22,
                               width: (radius + 22) * 2, height: (radius + 22) * 2))
    ctx.setFillColor(color)
    ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                               width: radius * 2, height: radius * 2))
}

dot(nodeA, radius: 74, color: srgb(0x3FDCA4))
dot(nodeB, radius: 74, color: srgb(0x5AA9FF))
dot(nodeC, radius: 84, color: srgb(0x3FDCA4))

let image = ctx.makeImage()!
let rep = NSBitmapImageRep(cgImage: image)
rep.size = NSSize(width: size, height: size)
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("png encode") }
try! png.write(to: URL(fileURLWithPath: output))
print("wrote \(output)")
