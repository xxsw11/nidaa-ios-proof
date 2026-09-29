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
    @State private var diagnostics = CredentialDiagnostics()
    @Environment(\.scenePhase) private var phase
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.caption)
            HStack(spacing: 8) {
                CredentialInput(text: $text, diagnostics: $diagnostics, title: title, id: id, contentType: contentType, secure: !visible)
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
            #if targetEnvironment(simulator)
            if ProcessInfo.processInfo.arguments.contains("-nidaa-ui-testing") {
                Text("فحص إدخال تجريبي")
                    .font(.caption2)
                    .accessibilityIdentifier(id + "Diagnostics")
                    .accessibilityValue(diagnostics.summary + ",bindingReady=\(text.count >= 8)")
            }
            #endif
        }
        .onChange(of: phase) { if $0 != .active { visible = false } }
        .onDisappear { visible = false }
    }
}

/// Test diagnostics contain only booleans, never text, lengths or credentials.
private struct CredentialDiagnostics: Equatable {
    var nativeReady = false
    var hasText = false
    var firstResponder = false
    var asciiKeyboard = false
    var secure = true
    var receivedSeveralEdits = false
    var summary: String {
        "nativeReady=\(nativeReady),hasText=\(hasText),firstResponder=\(firstResponder),asciiKeyboard=\(asciiKeyboard),secure=\(secure),receivedSeveralEdits=\(receivedSeveralEdits)"
    }
}

private struct CredentialInput: UIViewRepresentable {
    @Binding var text: String
    @Binding var diagnostics: CredentialDiagnostics
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
        // Setting a keyboard/AutoFill trait during every text edit is unnecessary
        // and can reconfigure the active system input session. Keep it stable.
        if field.textContentType != contentType { field.textContentType = contentType }
        if field.isSecureTextEntry != secure {
            let draft = text
            let selection = field.selectedTextRange
            field.isSecureTextEntry = secure
            // UIKit can reset its display when switching secure entry. Preserve
            // the same draft and selection on the same responder.
            field.text = draft
            if let selection { field.selectedTextRange = selection }
        } else if field.text != text { field.text = text }
    }
    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: CredentialInput
        weak var field: UITextField?
        private var edits = 0
        init(_ parent: CredentialInput) { self.parent = parent }
        @objc func done() { field?.resignFirstResponder() }
        @objc func changed(_ field: UITextField) {
            edits += 1
            parent.text = field.text ?? ""
            record(field)
        }
        func textFieldDidBeginEditing(_ textField: UITextField) { record(textField) }
        func textFieldDidEndEditing(_ textField: UITextField) { record(textField) }
        private func record(_ field: UITextField) {
            #if targetEnvironment(simulator)
            guard ProcessInfo.processInfo.arguments.contains("-nidaa-ui-testing") else { return }
            parent.diagnostics = CredentialDiagnostics(nativeReady: (field.text?.count ?? 0) >= 8,
                hasText: !(field.text ?? "").isEmpty, firstResponder: field.isFirstResponder,
                asciiKeyboard: field.keyboardType == .asciiCapable, secure: field.isSecureTextEntry,
                receivedSeveralEdits: edits >= 8)
            #endif
        }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder(); return true
        }
    }
}
#endif
