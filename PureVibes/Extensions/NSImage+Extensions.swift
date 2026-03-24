import SwiftUI
import AppKit

extension NSImage {
    func dominantColor() -> Color {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .black }
        
        let width = 50
        let height = 50
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var rawData = [UInt8](repeating: 0, count: width * height * 4)
        let bytesPerPixel = 4
        let bytesPerRow = bytesPerPixel * width
        let bitsPerComponent = 8
        
        guard let context = CGContext(data: &rawData, width: width, height: height, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return .black }
        
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Simple average calculation
        var totalR: CGFloat = 0, totalG: CGFloat = 0, totalB: CGFloat = 0
        let pixelCount = CGFloat(width * height)
        
        for i in stride(from: 0, to: rawData.count, by: 4) {
            totalR += CGFloat(rawData[i])
            totalG += CGFloat(rawData[i+1])
            totalB += CGFloat(rawData[i+2])
        }
        
        return Color(red: Double(totalR / pixelCount / 255.0),
                     green: Double(totalG / pixelCount / 255.0),
                     blue: Double(totalB / pixelCount / 255.0))
    }
    
    /// Returns a downscaled copy cached by pointer identity. Safe to call repeatedly.
    private static let thumbnailCache = NSCache<NSString, NSImage>()
    
    func thumbnail(maxSize: CGFloat = 100) -> NSImage {
        let cacheKey = "\(self.hash)_\(Int(maxSize))" as NSString
        if let cached = NSImage.thumbnailCache.object(forKey: cacheKey) { return cached }
        let scale = min(maxSize / max(size.width, 1), maxSize / max(size.height, 1), 1.0)
        if scale >= 1.0 { return self }
        let newSize = NSSize(width: size.width * scale, height: size.height * scale)
        let thumb = NSImage(size: newSize)
        thumb.lockFocus()
        self.draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .copy, fraction: 1.0)
        thumb.unlockFocus()
        NSImage.thumbnailCache.setObject(thumb, forKey: cacheKey)
        return thumb
    }

    func averageBrightness() -> Double {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0.5 }
        let size = 20
        var rawData = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &rawData, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 0.5 }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        var total = 0.0
        for i in stride(from: 0, to: rawData.count, by: 4) {
            total += 0.2126 * Double(rawData[i])   / 255.0
                  +  0.7152 * Double(rawData[i+1]) / 255.0
                  +  0.0722 * Double(rawData[i+2]) / 255.0
        }
        return total / Double(size * size)
    }

    func contrastRatio() -> Double {
        guard let cgImage = self.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 1.0 }
        let size = 20
        var rawData = [UInt8](repeating: 0, count: size * size * 4)
        guard let ctx = CGContext(data: &rawData, width: size, height: size,
                                  bitsPerComponent: 8, bytesPerRow: size * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return 1.0 }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))
        var luminances: [Double] = []
        for i in stride(from: 0, to: rawData.count, by: 4) {
            luminances.append(0.2126 * Double(rawData[i])   / 255.0
                            + 0.7152 * Double(rawData[i+1]) / 255.0
                            + 0.0722 * Double(rawData[i+2]) / 255.0)
        }
        luminances.sort()
        let cutoff   = max(1, luminances.count / 10)
        let darkAvg  = luminances.prefix(cutoff).reduce(0, +) / Double(cutoff)
        let lightAvg = luminances.suffix(cutoff).reduce(0, +) / Double(cutoff)
        guard darkAvg > 0 else { return lightAvg > 0 ? 10.0 : 1.0 }
        return lightAvg / darkAvg
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
