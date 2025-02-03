import Foundation

enum ImageError: Error {
    case failedToConvertToDataURL
}

extension LLMMessage {
    public mutating func add(image: ChatUINSImage, detail: LLMMessage.Image.Detail = .auto, maxSize: CGFloat? = nil) throws {
        try images.append(image.asLLMImage(detail: detail, maxSize: maxSize))
    }

    public mutating func add(audio: LLMMessage.Audio) {
        inputAudio.append(audio)
    }
}

public extension ChatUINSImage {
    func asLLMImage(detail: LLMMessage.Image.Detail = .auto, maxSize: CGFloat? = nil) throws -> LLMMessage.Image {
        let maxDim = min(maxSize ?? 2000, detail == .low ? 512 : 2000)
        guard let b64 = resizedWithMaxDimension(maxDimension: maxDim)?.asBase64DataURL() else {
            throw ImageError.failedToConvertToDataURL
        }
        return .init(url: b64, detail: detail)
    }
}
