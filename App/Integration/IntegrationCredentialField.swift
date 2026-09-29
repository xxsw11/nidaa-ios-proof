#if DEBUG
import SwiftUI
import UIKit

/// One UITextField retains focus/selection when visibility changes. Password
/// semantics stay native; no plaintext replacement view or AutoFill suppression.
struct IntegrationCredentialField: View {
    let title: String
    @Binding var text: String
    let id: String
    var contentType: UITextContentType? = nil
    var allowsVisibility = false
    @State private var visible = false
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption)
            HStack(spacing: 8) {
                CredentialInput(text: $text, title: title, id: id, contentType: contentType, secure: !visible)
                    .frame(minHeight: 48)
                if allowsVisibility {
                    Button { visible.toggle() } label: {
                        Image(systemName: visible ? "eye.slash" : "eye")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(visible ? "إخفاء كلمة المرور" : "إظهار كلمة المرور")
                    .accessibilityIdentifier(id + "Visibility")
                    .accessibilityValue(visible ? "visible" : "hidden")
                }
                PasteButton(payloadType: String.self) { values in
                    guard let value = values.first else { return }
                    text = value
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("لصق في " + title)
                .accessibilityIdentifier(id + "Paste")
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .onChange(of: phase) { if $0 != .active { visible = false } }
        .onDisappear { visible = false }
    }
}

private struct CredentialInput: UIViewRepresentable {
    @Binding var text: String
    let title: String
    let id: String
    let contentType: UITextContentType?
    let secure: Bool
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.keyboardType = .asciiCapable
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.spellCheckingType = .no
        field.textAlignment = .left
        field.semanticContentAttribute = .forceLeftToRight
        field.returnKeyType = .done
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.changed(_:)), for: .editingChanged)
        let toolbar = UIToolbar()
        let done = UIBarButtonItem(title: "تم", style: .done, target: context.coordinator, action: #selector(Coordinator.done))
        done.accessibilityIdentifier = "integrationKeyboardDone"
        toolbar.items = [UIBarButtonItem(systemItem: .flexibleSpace), done]
        toolbar.sizeToFit()
        field.inputAccessoryView = toolbar
        context.coordinator.field = field
        return field
    }
    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        field.placeholder = title
        field.accessibilityIdentifier = id
        field.accessibilityLabel = title
        field.textContentType = contentType
        if field.isSecureTextEntry != secure {
            let selection = field.selectedTextRange
            field.isSecureTextEntry = secure
            // UIKit can reset its display when switching secure entry. Preserve
            // the same draft and selection on the same responder.
            field.text = text
            if let selection { field.selectedTextRange = selection }
        } else if field.text != text { field.text = text }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CredentialInput
        weak var field: UITextField?
        init(_ parent: CredentialInput) { self.parent = parent }
        @objc func done() { field?.resignFirstResponder() }
        @objc func changed(_ field: UITextField) { parent.text = field.text ?? "" }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder(); return true
        }
    }
}
#endif
