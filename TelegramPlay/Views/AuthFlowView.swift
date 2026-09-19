import SwiftUI

struct AuthFlowView: View {
    @EnvironmentObject private var telegram: TelegramClientService
    @State private var phone = ""
    @State private var code = ""
    @State private var password = ""

    var body: some View {
        Form {
            switch telegram.authPhase {
            case .phone:
                Section("Phone number") {
                    TextField("+1 234 567 8900", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    Button("Send code") {
                        Task { await telegram.submitPhoneNumber(phone.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    .disabled(phone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            case .code:
                Section("Login code") {
                    TextField("12345", text: $code)
                        .keyboardType(.numberPad)
                    Button("Verify") {
                        Task { await telegram.submitCode(code.trimmingCharacters(in: .whitespacesAndNewlines)) }
                    }
                    .disabled(code.isEmpty)
                }
            case .password(let hint):
                Section("Two-step password") {
                    if !hint.isEmpty {
                        Text("Hint: \(hint)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    SecureField("Password", text: $password)
                    Button("Sign in") {
                        Task { await telegram.submitPassword(password) }
                    }
                    .disabled(password.isEmpty)
                }
            default:
                EmptyView()
            }

            if let status = telegram.statusMessage {
                Section {
                    Text(status).foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Telegram sign in")
    }
}
