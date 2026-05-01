#!/usr/bin/env swift
import AppKit
import Foundation

let arguments = CommandLine.arguments.dropFirst()
guard let outputPath = arguments.first else {
    fputs("usage: generate_app_icon.swift <output.icns>\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: outputPath)
let fileManager = FileManager.default
let iconsetURL = outputURL
    .deletingLastPathComponent()
    .appendingPathComponent("CrawlBar.iconset", isDirectory: true)

try? fileManager.removeItem(at: iconsetURL)
try fileManager.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
try fileManager.createDirectory(at: outputURL.deletingLastPathComponent(), withIntermediateDirectories: true)

let variants: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for (name, size) in variants {
    let image = drawIcon(size: size)
    try writePNG(image, to: iconsetURL.appendingPathComponent(name))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()
if process.terminationStatus != 0 {
    fputs("iconutil failed\n", stderr)
    exit(process.terminationStatus)
}

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    defer { image.unlockFocus() }

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let tile = NSBezierPath(roundedRect: rect.insetBy(dx: size * 0.04, dy: size * 0.04), xRadius: size * 0.21, yRadius: size * 0.21)
    NSColor(calibratedRed: 0.075, green: 0.086, blue: 0.105, alpha: 1).setFill()
    tile.fill()

    NSColor(calibratedRed: 0.18, green: 0.43, blue: 0.82, alpha: 1).setStroke()
    let line = NSBezierPath()
    line.lineWidth = size * 0.048
    line.lineCapStyle = .round
    line.move(to: NSPoint(x: size * 0.22, y: size * 0.64))
    line.curve(
        to: NSPoint(x: size * 0.78, y: size * 0.64),
        controlPoint1: NSPoint(x: size * 0.38, y: size * 0.83),
        controlPoint2: NSPoint(x: size * 0.62, y: size * 0.83))
    line.move(to: NSPoint(x: size * 0.22, y: size * 0.36))
    line.curve(
        to: NSPoint(x: size * 0.78, y: size * 0.36),
        controlPoint1: NSPoint(x: size * 0.38, y: size * 0.17),
        controlPoint2: NSPoint(x: size * 0.62, y: size * 0.17))
    line.stroke()

    drawDot(NSPoint(x: size * 0.22, y: size * 0.64), size: size, color: NSColor(calibratedRed: 0.18, green: 0.43, blue: 0.82, alpha: 1))
    drawDot(NSPoint(x: size * 0.78, y: size * 0.64), size: size, color: NSColor(calibratedRed: 0.35, green: 0.40, blue: 0.95, alpha: 1))
    drawDot(NSPoint(x: size * 0.22, y: size * 0.36), size: size, color: NSColor(calibratedRed: 0.20, green: 0.73, blue: 0.61, alpha: 1))
    drawDot(NSPoint(x: size * 0.78, y: size * 0.36), size: size, color: .white)

    drawMiniNotion(in: NSRect(x: size * 0.66, y: size * 0.24, width: size * 0.24, height: size * 0.24))
    return image
}

func drawDot(_ center: NSPoint, size: CGFloat, color: NSColor) {
    color.setFill()
    NSBezierPath(ovalIn: NSRect(
        x: center.x - size * 0.055,
        y: center.y - size * 0.055,
        width: size * 0.11,
        height: size * 0.11)).fill()
}

func drawMiniNotion(in rect: NSRect) {
    let tile = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.2, yRadius: rect.width * 0.2)
    NSColor.white.setFill()
    tile.fill()
    NSColor(calibratedWhite: 0.06, alpha: 1).setStroke()
    tile.lineWidth = max(1, rect.width * 0.08)
    tile.stroke()
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    NSString(string: "N").draw(
        in: rect.offsetBy(dx: 0, dy: -rect.height * 0.08),
        withAttributes: [
            .font: NSFont.systemFont(ofSize: rect.width * 0.72, weight: .heavy),
            .foregroundColor: NSColor(calibratedWhite: 0.04, alpha: 1),
            .paragraphStyle: paragraph,
        ])
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw CocoaError(.fileWriteUnknown)
    }
    try data.write(to: url)
}
