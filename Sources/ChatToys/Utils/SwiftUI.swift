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


private struct ContentSizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}

extension View {
    func measureSize(_ callback: @escaping (CGSize) -> Void) -> some View {
        background(GeometryReader(content: { geo in
            Color.clear
                .preference(key: ContentSizePreferenceKey.self, value: geo.size)
        }))
        .onPreferenceChange(ContentSizePreferenceKey.self) { size in
            callback(size)
        }
    }
}
