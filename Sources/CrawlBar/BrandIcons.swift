import AppKit
import CrawlBarCore
import SwiftUI

enum CrawlBarBrandPalette {
    static func accent(for appID: CrawlAppID, manifest: CrawlAppManifest?) -> NSColor {
        switch appID.rawValue {
        case "gitcrawl":
            NSColor(calibratedWhite: 0.08, alpha: 1)
        case "slacrawl":
            NSColor(calibratedRed: 0.25, green: 0.16, blue: 0.32, alpha: 1)
        case "discrawl":
            NSColor(calibratedRed: 0.35, green: 0.40, blue: 0.95, alpha: 1)
        case "notcrawl":
            NSColor(calibratedWhite: 0.08, alpha: 1)
        default:
            NSColor(hex: manifest?.branding.accentColor ?? "#6E6E73")
        }
    }
}

enum CrawlBarCrawlerTitle {
    static func text(for appID: CrawlAppID, manifest: CrawlAppManifest?) -> String {
        let source = manifest?.displayName.nilIfBlank ?? appID.rawValue
        guard let binary = manifest?.binary.name.nilIfBlank, binary != source else {
            return source
        }
        return "\(source) (\(binary))"
    }
}

enum CrawlBarIconFactory {
    static func image(for appID: CrawlAppID, manifest: CrawlAppManifest?, size: CGFloat = 32) -> NSImage {
        if let image = Self.brandedImage(for: manifest, size: size) {
            return image
        }
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        Self.drawTile(appID: appID, manifest: manifest, rect: NSRect(x: 0, y: 0, width: size, height: size))
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    static func menuBarImage(size: CGFloat = 18) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        let stroke = NSColor.labelColor
        stroke.setStroke()
        let line = NSBezierPath()
        line.lineWidth = max(1.6, size * 0.1)
        let inset = size * 0.19
        line.move(to: NSPoint(x: inset, y: size * 0.68))
        line.curve(
            to: NSPoint(x: size - inset, y: size * 0.68),
            controlPoint1: NSPoint(x: size * 0.38, y: size * 0.94),
            controlPoint2: NSPoint(x: size * 0.62, y: size * 0.94))
        line.move(to: NSPoint(x: inset, y: size * 0.32))
        line.curve(
            to: NSPoint(x: size - inset, y: size * 0.32),
            controlPoint1: NSPoint(x: size * 0.38, y: size * 0.06),
            controlPoint2: NSPoint(x: size * 0.62, y: size * 0.06))
        line.stroke()

        for point in [
            NSPoint(x: inset, y: size * 0.68),
            NSPoint(x: size - inset, y: size * 0.68),
            NSPoint(x: inset, y: size * 0.32),
            NSPoint(x: size - inset, y: size * 0.32),
        ] {
            let dot = NSBezierPath(ovalIn: NSRect(
                x: point.x - size * 0.105,
                y: point.y - size * 0.105,
                width: size * 0.21,
                height: size * 0.21))
            stroke.setFill()
            dot.fill()
        }
        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private static func brandedImage(for manifest: CrawlAppManifest?, size: CGFloat) -> NSImage? {
        if let iconPath = manifest?.branding.iconPath?.nilIfBlank {
            let expandedPath = NSString(string: iconPath).expandingTildeInPath
            if let image = NSImage(contentsOfFile: expandedPath) {
                return Self.sizedImage(image, size: size)
            }
        }
        if let bundleIdentifier = manifest?.branding.bundleIdentifier?.nilIfBlank,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        {
            return Self.sizedImage(NSWorkspace.shared.icon(forFile: appURL.path), size: size)
        }
        return nil
    }

    private static func sizedImage(_ source: NSImage, size: CGFloat) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()
        source.draw(
            in: NSRect(x: 0, y: 0, width: size, height: size),
            from: .zero,
            operation: .sourceOver,
            fraction: 1)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private static func drawTile(appID: CrawlAppID, manifest: CrawlAppManifest?, rect: NSRect) {
        let radius = rect.width * 0.22
        let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 1, dy: 1), xRadius: radius, yRadius: radius)
        switch appID.rawValue {
        case "notcrawl":
            NSColor.white.setFill()
            tile.fill()
            NSColor(calibratedWhite: 0.12, alpha: 1).setStroke()
            tile.lineWidth = max(1, rect.width * 0.035)
            tile.stroke()
            Self.drawNotionN(in: rect)
        default:
            let accent = CrawlBarBrandPalette.accent(for: appID, manifest: manifest)
            accent.withAlphaComponent(0.16).setFill()
            tile.fill()
            accent.withAlphaComponent(0.32).setStroke()
            tile.lineWidth = max(1, rect.width * 0.035)
            tile.stroke()
            switch appID.rawValue {
            case "gitcrawl":
                Self.drawGitGlyph(in: rect, color: accent)
            case "slacrawl":
                Self.drawSlackGlyph(in: rect)
            case "discrawl":
                Self.drawDiscordGlyph(in: rect, color: accent)
            default:
                Self.drawTerminalGlyph(in: rect, color: accent)
            }
        }
    }

    private static func drawNotionN(in rect: NSRect) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let fontSize = rect.width * 0.64
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor(calibratedWhite: 0.05, alpha: 1),
            .paragraphStyle: paragraph,
        ]
        NSString(string: "N").draw(
            in: rect.offsetBy(dx: 0, dy: -rect.height * 0.06),
            withAttributes: attributes)
    }

    private static func drawGitGlyph(in rect: NSRect, color: NSColor) {
        color.setStroke()
        color.setFill()
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let left = NSPoint(x: rect.minX + rect.width * 0.28, y: rect.midY)
        let top = NSPoint(x: rect.maxX - rect.width * 0.27, y: rect.maxY - rect.height * 0.28)
        let bottom = NSPoint(x: rect.maxX - rect.width * 0.27, y: rect.minY + rect.height * 0.28)
        let path = NSBezierPath()
        path.lineWidth = max(2, rect.width * 0.08)
        path.lineCapStyle = .round
        path.move(to: left)
        path.line(to: center)
        path.line(to: top)
        path.move(to: center)
        path.line(to: bottom)
        path.stroke()
        for point in [left, center, top, bottom] {
            NSBezierPath(ovalIn: NSRect(
                x: point.x - rect.width * 0.085,
                y: point.y - rect.width * 0.085,
                width: rect.width * 0.17,
                height: rect.width * 0.17)).fill()
        }
    }

    private static func drawSlackGlyph(in rect: NSRect) {
        let colors = [
            NSColor(calibratedRed: 0.20, green: 0.73, blue: 0.61, alpha: 1),
            NSColor(calibratedRed: 0.22, green: 0.53, blue: 0.92, alpha: 1),
            NSColor(calibratedRed: 0.91, green: 0.18, blue: 0.39, alpha: 1),
            NSColor(calibratedRed: 0.94, green: 0.72, blue: 0.18, alpha: 1),
        ]
        let w = rect.width * 0.16
        let h = rect.height * 0.43
        let r = w * 0.5
        let center = NSPoint(x: rect.midX, y: rect.midY)
        let shapes = [
            (NSRect(x: center.x - w * 1.15, y: center.y - h * 0.12, width: w, height: h), CGFloat(0)),
            (NSRect(x: center.x + w * 0.15, y: center.y - h * 0.88, width: h, height: w), CGFloat(0)),
            (NSRect(x: center.x + w * 0.15, y: center.y - h * 0.12, width: w, height: h), CGFloat(0)),
            (NSRect(x: center.x - h * 0.88, y: center.y + w * 0.15, width: h, height: w), CGFloat(0)),
        ]
        for index in shapes.indices {
            colors[index].setFill()
            NSBezierPath(
                roundedRect: shapes[index].0,
                xRadius: r,
                yRadius: r).fill()
        }
    }

    private static func drawDiscordGlyph(in rect: NSRect, color: NSColor) {
        color.setFill()
        let body = NSBezierPath(roundedRect: rect.insetBy(dx: rect.width * 0.22, dy: rect.height * 0.28), xRadius: rect.width * 0.16, yRadius: rect.width * 0.16)
        body.fill()
        NSColor.white.withAlphaComponent(0.95).setFill()
        for x in [rect.midX - rect.width * 0.11, rect.midX + rect.width * 0.11] {
            NSBezierPath(ovalIn: NSRect(
                x: x - rect.width * 0.035,
                y: rect.midY - rect.height * 0.025,
                width: rect.width * 0.07,
                height: rect.width * 0.07)).fill()
        }
        let smile = NSBezierPath()
        smile.lineWidth = max(1.3, rect.width * 0.035)
        smile.move(to: NSPoint(x: rect.midX - rect.width * 0.1, y: rect.midY - rect.height * 0.13))
        smile.curve(
            to: NSPoint(x: rect.midX + rect.width * 0.1, y: rect.midY - rect.height * 0.13),
            controlPoint1: NSPoint(x: rect.midX - rect.width * 0.04, y: rect.midY - rect.height * 0.19),
            controlPoint2: NSPoint(x: rect.midX + rect.width * 0.04, y: rect.midY - rect.height * 0.19))
        smile.stroke()
    }

    private static func drawTerminalGlyph(in rect: NSRect, color: NSColor) {
        color.setStroke()
        let path = NSBezierPath()
        path.lineWidth = max(1.8, rect.width * 0.06)
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        path.move(to: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.midY + rect.height * 0.14))
        path.line(to: NSPoint(x: rect.midX - rect.width * 0.02, y: rect.midY))
        path.line(to: NSPoint(x: rect.minX + rect.width * 0.28, y: rect.midY - rect.height * 0.14))
        path.move(to: NSPoint(x: rect.midX + rect.width * 0.08, y: rect.midY - rect.height * 0.16))
        path.line(to: NSPoint(x: rect.maxX - rect.width * 0.24, y: rect.midY - rect.height * 0.16))
        path.stroke()
    }
}

struct CrawlBarBrandIcon: View {
    let manifest: CrawlAppManifest?
    let appID: CrawlAppID

    var body: some View {
        GeometryReader { proxy in
            Image(nsImage: CrawlBarIconFactory.image(
                for: self.appID,
                manifest: self.manifest,
                size: max(16, min(proxy.size.width, proxy.size.height))))
            .resizable()
            .interpolation(.high)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private extension NSColor {
    convenience init(hex: String) {
        let trimmed = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let scanner = Scanner(string: trimmed)
        var value: UInt64 = 0
        scanner.scanHexInt64(&value)
        self.init(
            calibratedRed: Double((value >> 16) & 0xff) / 255,
            green: Double((value >> 8) & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            alpha: 1)
    }
}
