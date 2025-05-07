import Foundation

#if os(iOS)
import UIKit

public typealias ChatUINSImage = UIImage

extension UIImage {
    func resizedWithMaxDimension(maxDimension: CGFloat) -> UIImage? {
        let aspect = size.width / size.height
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspect)
        } else {
            newSize = CGSize(width: maxDimension * aspect, height: maxDimension)
        }
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { (context) in
            self.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    func asBase64DataURL() -> URL? {
        guard let data = self.jpegData(compressionQuality: 0.5) else {
            return nil
        }
        let base64String = data.base64EncodedString()
        return URL(string: "data:image/jpeg;base64,\(base64String)")
    }
}

#elseif os(macOS)

import AppKit

public typealias ChatUINSImage = NSImage

extension NSImage {
    func resizedWithMaxDimension(maxDimension: CGFloat) -> NSImage? {
        let aspect = size.width / size.height
        var newSize: CGSize
        if size.width > size.height {
            newSize = CGSize(width: maxDimension, height: maxDimension / aspect)
        } else {
            newSize = CGSize(width: maxDimension * aspect, height: maxDimension)
        }
        return self.resizeImage(toPixelDimensions: newSize)
//        let newImage = NSImage(size: newSize)
//        newImage.lockFocus()
//        draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1)
//        newImage.unlockFocus()
//        return newImage
    }

    func asBase64DataURL() -> URL? {
        guard let tiffData = tiffRepresentation else {
            return nil
        }
        guard let bitmap = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        guard let data = bitmap.representation(using: .jpeg, properties: [:]) else {
            return nil
        }
        let base64String = data.base64EncodedString()
        return URL(string: "data:image/jpeg;base64,\(base64String)")
    }
}

extension NSImage {
    func resizeImage(toPixelDimensions newSize: NSSize) -> NSImage? {
        let sourceImage = self
        if !sourceImage.isValid { return nil }
        
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(newSize.width),
            pixelsHigh: Int(newSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }
        
        rep.size = newSize
        
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        sourceImage.draw(in: NSRect(x: 0, y: 0, width: newSize.width, height: newSize.height),
                        from: .zero,
                        operation: .copy,
                        fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()
        
        let newImage = NSImage(size: newSize)
        newImage.addRepresentation(rep)
        return newImage
    }
}

#endif

