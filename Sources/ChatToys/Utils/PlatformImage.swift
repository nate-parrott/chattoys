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
        let newImage = NSImage(size: newSize)
        newImage.lockFocus()
        draw(in: NSRect(origin: .zero, size: newSize), from: NSRect(origin: .zero, size: size), operation: .sourceOver, fraction: 1)
        newImage.unlockFocus()
        return newImage
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

#endif

