import Foundation

enum ImageError: Error {
    case failedToConvertToDataURL
}

extension LLMMessage {
    public mutating func add(image: ChatUINSImage, detail: LLMMessage.Image.Detail = .auto, maxSize: CGFloat? = nil) throws {
        let maxDim = min(maxSize ?? 2000, detail == .low ? 512 : 2000)
        guard let b64 = image.resizedWithMaxDimension(maxDimension: maxDim)?.asBase64DataURL() else {
            throw ImageError.failedToConvertToDataURL
        }
        images.append(.init(url: b64, detail: detail))
    }
}
