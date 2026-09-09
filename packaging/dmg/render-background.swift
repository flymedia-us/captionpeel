#!/usr/bin/env swift
import AppKit

let windowSize = NSSize(width: 660, height: 400)

func drawBackground() {
    let bounds = NSRect(origin: .zero, size: windowSize)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.14, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.12, blue: 0.29, alpha: 1),
    ])!
    gradient.draw(in: bounds, angle: 22)

    NSColor(calibratedRed: 0.18, green: 0.42, blue: 0.94, alpha: 0.12).setFill()
    NSBezierPath(ovalIn: NSRect(x: -100, y: 190, width: 430, height: 330)).fill()
    NSColor(calibratedRed: 1, green: 0.35, blue: 0.29, alpha: 0.08).setFill()
    NSBezierPath(ovalIn: NSRect(x: 390, y: -120, width: 390, height: 330)).fill()

    let title = "CaptionPeel" as NSString
    let titleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 28, weight: .semibold),
        .foregroundColor: NSColor(calibratedWhite: 0.98, alpha: 1),
    ]
    let titleSize = title.size(withAttributes: titleAttributes)
    title.draw(
        at: NSPoint(x: (windowSize.width - titleSize.width) / 2, y: 352),
        withAttributes: titleAttributes
    )

    let subtitle = "Drag to Applications" as NSString
    let subtitleAttributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium),
        .foregroundColor: NSColor(calibratedWhite: 0.72, alpha: 1),
    ]
    let subtitleSize = subtitle.size(withAttributes: subtitleAttributes)
    subtitle.draw(
        at: NSPoint(x: (windowSize.width - subtitleSize.width) / 2, y: 328),
        withAttributes: subtitleAttributes
    )

    let chevron = NSBezierPath()
    chevron.lineCapStyle = .round
    chevron.lineJoinStyle = .round
    chevron.lineWidth = 8
    chevron.move(to: NSPoint(x: 316, y: 232))
    chevron.line(to: NSPoint(x: 346, y: 210))
    chevron.line(to: NSPoint(x: 316, y: 188))
    NSColor(calibratedWhite: 1, alpha: 0.38).setStroke()
    chevron.stroke()
}

func writePNG(scale: CGFloat, url: URL) throws {
    guard let representation = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(windowSize.width * scale),
        pixelsHigh: Int(windowSize.height * scale),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        throw NSError(domain: "CaptionPeelDMG", code: 1)
    }
    representation.size = windowSize
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: representation)
    drawBackground()
    NSGraphicsContext.restoreGraphicsState()
    guard let data = representation.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "CaptionPeelDMG", code: 2)
    }
    try data.write(to: url, options: .atomic)
}

let directory = URL(fileURLWithPath: CommandLine.arguments[0])
    .resolvingSymlinksInPath()
    .deletingLastPathComponent()
try writePNG(scale: 1, url: directory.appendingPathComponent("background.png"))
try writePNG(scale: 2, url: directory.appendingPathComponent("background@2x.png"))

let twoXPath = directory.appendingPathComponent("background@2x.png").path
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
process.arguments = ["-s", "dpiWidth", "144", "-s", "dpiHeight", "144", twoXPath]
try process.run()
process.waitUntilExit()

print("wrote \(directory.path)/background.png")
print("wrote \(directory.path)/background@2x.png")
