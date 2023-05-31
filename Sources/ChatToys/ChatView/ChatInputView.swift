import SwiftUI

public struct ChatInputView: View {
    public let placeholder: String
    @Binding public var text: String
    public let sendAction: () -> Void

    public init(placeholder: String, text: Binding<String>, sendAction: @escaping () -> Void) {
        self.placeholder = placeholder
        self._text = text
        self.sendAction = sendAction
    }

    public var body: some View {
        HStack(spacing: 10) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
            Button(action: sendAction) {
                Image(systemName: "arrow.up.circle.fill")
                    .foregroundColor(.accentColor)
                    .font(.system(size: 30))
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(text.isEmpty)
        }
        .onSubmit {
            if !text.isEmpty {
                sendAction()
            }
        }
        .padding(10)
    }
}
