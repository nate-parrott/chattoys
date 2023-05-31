import SwiftUI

extension View {
    func onAppearOrChange<T: Equatable>(of value: T, perform action: @escaping (T) -> Void) -> some View {
        onAppear {
            action(value)
        }
        .onChange(of: value, perform: action)
    }
}

extension Animation {
    static func niceDefault(duration: TimeInterval) -> Animation {
        .timingCurve(0.25, 0.1, 0.25, 1, duration: duration)
    }
    static var niceDefault: Animation { .niceDefault(duration: 0.3) }
}
