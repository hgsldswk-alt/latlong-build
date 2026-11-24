import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct CardContent: Equatable, Sendable {
    let heading: String
    let name: String?
    let coordinates: String?
    let accuracy: String?
    let appName: String
    let caption: String
    let qrLabel: String
    let storeURL: URL?
    let retry: Int

    var accessibilityText: String { [heading, name, coordinates, accuracy, caption].compactMap { $0 }.joined(separator: " · ") }
}

enum CardRenderer {
    static func png(_ card: CardContent) -> Data? {
        guard let context = CGContext(data: nil, width: 1080, height: 1350, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        let teal = CGColor(red: 0, green: 0.408, blue: 0.459, alpha: 1)
        let ink = CGColor(red: 0.063, green: 0.149, blue: 0.208, alpha: 1)
        let muted = CGColor(red: 0.235, green: 0.341, blue: 0.4, alpha: 1)
        let white = CGColor(gray: 1, alpha: 1)

        context.scaleBy(x: 3, y: 3)
        context.setFillColor(CGColor(red: 0.945, green: 0.961, blue: 0.973, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 360, height: 450))
        context.setFillColor(teal)
        context.fill(CGRect(x: 0, y: 440, width: 360, height: 10))
        context.setStrokeColor(teal)
        context.setLineWidth(1.5)
        context.strokeEllipse(in: CGRect(x: 26, y: 354, width: 40, height: 40))
        context.move(to: CGPoint(x: 20, y: 374)); context.addLine(to: CGPoint(x: 72, y: 374))
        context.move(to: CGPoint(x: 46, y: 348)); context.addLine(to: CGPoint(x: 46, y: 400))
        context.strokePath()
        context.fillEllipse(in: CGRect(x: 43, y: 371, width: 6, height: 6))

        line(card.appName, at: CGPoint(x: 26, y: 319), size: 14, color: teal, strong: true, in: context)
        line(card.heading, at: CGPoint(x: 26, y: 268), size: 32, color: ink, strong: true, in: context)
        if let name = card.name { line(name, at: CGPoint(x: 26, y: 221), size: 19, color: ink, strong: true, in: context) }
        if let coordinates = card.coordinates {
            line(coordinates, at: CGPoint(x: 26, y: 187), size: 17, color: ink, strong: false, in: context)
        }
        if let accuracy = card.accuracy { line(accuracy, at: CGPoint(x: 26, y: 157), size: 15, color: muted, strong: false, in: context) }
        line(card.caption, at: CGPoint(x: 26, y: 51), size: 12, color: teal, strong: true, width: 214, in: context)
        let qrBox = CGRect(x: 250, y: 30, width: 84, height: 84)
        context.setFillColor(white)
        context.fill(qrBox)
        if let url = card.storeURL, let qr = CardQR.image(for: url) {
            context.interpolationQuality = .none
            context.draw(qr, in: qrBox.insetBy(dx: 10, dy: 10))
        } else {
            context.setStrokeColor(teal)
            context.setLineDash(phase: 0, lengths: [3, 3])
            context.stroke(qrBox.insetBy(dx: 2, dy: 2))
            context.setLineDash(phase: 0, lengths: [])
            line(card.qrLabel, at: CGPoint(x: 258, y: 67), size: 10, color: teal, strong: true, width: 68, in: context)
        }
        guard let image = context.makeImage() else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    private static func line(_ text: String, at position: CGPoint, size: CGFloat, color: CGColor,
                             strong: Bool, width: CGFloat = 308, in context: CGContext) {
        let font = CTFontCreateWithName((strong ? "HelveticaNeue-Bold" : "HelveticaNeue") as CFString, size, nil)
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let textLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        let fitted = CTLineCreateTruncatedLine(textLine, Double(width), .end, ellipsis) ?? textLine
        context.textPosition = position
        CTLineDraw(fitted, context)
    }
}
