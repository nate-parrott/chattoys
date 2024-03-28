import SwiftUI

public struct StreamingTextDemoView: View {
    public init() {}
    // 5 lorem ipsum sentences
    let sampleText = """
        Lorem ipsum dolor sit amet, consectetur adipiscing elit. Sed non risus. Suspendisse lectus tortor, dignissim sit amet, adipiscing nec, ultricies sed, dolor. Cras elementum ultrices diam. Maecenas ligula massa, varius a, semper congue, euismod non, mi.
        Proin porttitor, orci nec nonummy molestie, enim est eleifend mi, non fermentum diam nisl sit amet erat. Duis semper. Duis arcu massa, scelerisque vitae, consequat in, pretium a, enim. Pellentesque congue.
        Ut in risus volutpat libero pharetra tempor. Cras vestibulum bibendum augue. Praesent egestas leo in pede. Praesent blandit odio eu enim. Pellentesque sed dui ut augue blandit sodales.
        Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Aliquam nibh. Mauris ac mauris sed pede pellentesque fermentum. Maecenas adipiscing ante non diam sodales hendrerit.
        Ut velit mauris, egestas sed, gravida nec, ornare ut, mi. Aenean ut orci vel massa suscipit pulvinar. Nulla sollicitudin. Fusce varius, ligula non tempus aliquam, nunc turpis ullamcorper nibh, in tempus sapien eros vitae ligula.
        """

    @State private var slider: Double = 0

    // Show a slider and a streamingtext view that shows a truncated copy of the sample text

    public var body: some View {
        let truncated = sampleText.prefix(Int(slider)).components(separatedBy: " ").dropLast().joined(separator: " ")
        VStack(alignment: .leading) {
            Slider(value: $slider, in: 0...Double(sampleText.count), step: 5)

            StreamingText(text: String(truncated), color: .black)
            .lineLimit(nil)
            .multilineTextAlignment(.leading)
        }
        .padding()
        .frame(width: 300, height: 300, alignment: .topLeading)
        .background(.white)
        .font(.system(size: 18))
    }
}

public struct StreamingText: View {
    public var text: String
    public var color: Color

    public init(text: String, color: Color) {
        self.text = text
        self.color = color
    }

    @StateObject private var coord = StreamingTextCoordinator()

    public var body: some View {
        coord.swifuiText(color: color)
            .onAppearOrChange(of: text, perform: { coord.text = $0 })
    }
}


class StreamingTextCoordinator: ObservableObject {
    @Published var text: String = "" {
        didSet {
            if text.count > oldValue.count {
                velocityTracker.addSample(Double(text.count))
                let charsPerSec = max(2, velocityTracker.velocity)

                // Don't let new items have a greater alpha than the last item in the string already
                let maxAlphaForNewItems: Double = alphas.max(by: { $0.0 < $1.0 })?.1 ?? 1.0

                animatingTextPos = true
                // Stagger fade-ins based on velocity tracker
                let newChars = text.count - oldValue.count
                for offset in 0..<newChars {
                    let idx = oldValue.count + offset
                    let delay = TimeInterval(offset) / charsPerSec
                    let startingAlpha = -delay * fadeDuration // set negative alpha to delay visibility. Need more negative alpha if speed is higher
                    alphas[idx] = min(maxAlphaForNewItems, startingAlpha)
                }
            }
        }
    }
    @Published private(set) var alphas = [Int: Double]()

    func swifuiText(color: Color) -> Text {
        if alphas.isEmpty {
            return Text(text).foregroundColor(color)
        }
        let fullyFilledIdx = alphas.keys.min()!
        
        let final = Text(text.prefix(fullyFilledIdx)).foregroundColor(color)
        var rest = [Text]()

        for (i, char) in text.enumerated().dropFirst(fullyFilledIdx) {
            let alpha = max(0, alphas[i] ?? 1)
            rest.append(Text(String(char)).foregroundColor(color.opacity(alpha)))
        }

        return ([final] + rest).reduce(Text(""), +)

//        let wipeStart = Int(floor(textPos))
//        var filledText = Text(text.prefix(wipeStart)).foregroundColor(color)
//        
//        let wipeChars = Array(text.dropFirst(wipeStart)).prefix(wipeLength)
//        for (i, char) in wipeChars.enumerated() {
//            let alpha = remap(x: Double(wipeStart + i), domainStart: Double(wipeStart), domainEnd: Double(wipeStart + wipeLength), rangeStart: 1, rangeEnd: 0)
//            filledText += Text("\(char)").foregroundColor(color.opacity(alpha))
//        }
    }

    let framerate: TimeInterval = 30
    let fadeDuration: TimeInterval = 0.3


    private let velocityTracker = VelocityTracker(lookBack: 3)
    private var animatingTextPos: Bool {
        get { animatingTextPosTimer != nil }
        set {
            if newValue != animatingTextPos {
                if newValue {
                    animatingTextPosTimer = Timer(timeInterval: 1.0 / framerate, repeats: true, block: { [weak self] _ in
                        self?.tick()
                    })
                    RunLoop.main.add(animatingTextPosTimer!, forMode: .common)
                } else {
                    animatingTextPosTimer?.invalidate()
                    animatingTextPosTimer = nil
                }
            }
        }
    }
    private var animatingTextPosTimer: Timer?

    private func tick() {
        let delta = 1.0 / fadeDuration / framerate
        for (idx, alpha) in alphas {
            let newAlpha = alpha + delta
            if newAlpha >= 1 {
                alphas.removeValue(forKey: idx)
            } else {
                alphas[idx] = newAlpha
            }
        }

        if alphas.isEmpty {
            animatingTextPos = false
        }
    }
}


private class VelocityTracker {
    // MARK: - Model
    private struct Sample {
        var time: TimeInterval
        var value: Double
    }
    private var samples = [Sample]()

    // MARK: - API

    init(lookBack: TimeInterval = 1.0 / 15) { self.lookBack = lookBack }


    func addSample(_ val: Double) {
        samples.append(.init(time: CACurrentMediaTime(), value: val))
        trim()
    }

    var velocity: Double {
        trim()
        if let firstSample = samples.first, let lastSample = samples.last {
            let timeDelta = CACurrentMediaTime() - firstSample.time
            let distDelta = lastSample.value - firstSample.value
            if timeDelta > 0 {
                return distDelta / timeDelta
            }
        }
        return 0
    }

    // MARK: - Helpers
    private let lookBack: TimeInterval

    private func trim() {
        let now = CACurrentMediaTime()
        while let f = samples.first, now - f.time > lookBack {
            samples.removeFirst()
        }
    }
}

// MARK: - Math helpers

private func clamp(_ x: Double) -> Double {
    return max(0, min(1, x))
}

private func remap(x: CGFloat, domainStart: CGFloat, domainEnd: CGFloat, rangeStart: CGFloat, rangeEnd: CGFloat) -> CGFloat {
    if domainStart == domainEnd {
        return rangeStart
    }
    let t = (x - domainStart) / (domainEnd - domainStart)
    return rangeStart + (rangeEnd - rangeStart) * clamp(t)
}

#Preview {
    StreamingTextDemoView()
}
