import AppKit
import ImageIO

final class RoomArtwork {
    private let assets: [String: CGImage]

    init(layout: RoomLayout) {
        var assets: [String: CGImage] = [:]
        let directory = RoomResources.root().appendingPathComponent("layers")
        for layer in layout.layers where assets[layer.png] == nil {
            let url = directory.appendingPathComponent(layer.png)
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
               let cropped = image.cropping(to: layer.source.rect) {
                assets[layer.png] = cropped
            }
        }
        self.assets = assets
    }

    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    func hasAssets(for layout: RoomLayout) -> Bool {
        layout.layers.allSatisfy { assets[$0.png] != nil }
    }

    func draw(_ layout: RoomLayout, in viewport: CGRect, background: CGImage?) {
        guard viewport.width > 0, viewport.height > 0 else { return }
        NSColor(srgbRed: 0.16, green: 0.17, blue: 0.18, alpha: 1).setFill()
        viewport.fill()
        if let background {
            let scale = max(viewport.width / CGFloat(background.width), viewport.height / CGFloat(background.height))
            let size = CGSize(width: CGFloat(background.width) * scale, height: CGFloat(background.height) * scale)
            let rect = CGRect(x: viewport.midX - size.width / 2, y: viewport.midY - size.height / 2,
                              width: size.width, height: size.height)
            draw(background, in: rect)
        }
        let transform = RoomTransform(canvas: CGSize(width: layout.canvasWidth, height: layout.canvasHeight), viewport: viewport)
        for layer in layout.ordered where layer.visible != false {
            guard let image = assets[layer.png] else { continue }
            draw(image, in: layout.viewportDestination(layer, transform: transform))
        }
    }

    func thumbnail(for component: RoomComponent) -> NSImage {
        let bounds = component.bounds
        let size = CGSize(width: 96, height: 54)
        return NSImage(size: size, flipped: true) { [self] rect in
            let transform = RoomTransform(canvas: bounds.size, viewport: rect)
            for layer in component.layers {
                guard let image = assets[layer.png] else { continue }
                let source = (layer.target ?? layer.source).rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
                draw(image, in: transform.rect(source))
            }
            return true
        }
    }

    func hitTest(_ point: CGPoint, layout: RoomLayout, transform: RoomTransform) -> UUID? {
        for layer in layout.ordered.reversed() where layer.visible != false {
            guard let id = layer.placementID, let image = assets[layer.png] else { continue }
            let rect = layout.viewportDestination(layer, transform: transform)
            guard rect.contains(point) else { continue }
            let x = Int((point.x - rect.minX) / rect.width * CGFloat(image.width))
            let y = Int((point.y - rect.minY) / rect.height * CGFloat(image.height))
            guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
                  let context = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8,
                                          bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let data = context.data else { continue }
            context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            if data.load(fromByteOffset: 3, as: UInt8.self) > 48 { return id }
        }
        return nil
    }

    private func draw(_ image: CGImage, in rect: CGRect) {
        NSImage(cgImage: image, size: rect.size).draw(in: rect, from: .zero, operation: .sourceOver,
                                                     fraction: 1, respectFlipped: true,
                                                     hints: [.interpolation: NSImageInterpolation.high])
    }
}
