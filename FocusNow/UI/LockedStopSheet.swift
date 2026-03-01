import SwiftUI

struct LockedStopSheet: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @State private var pin: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Locked Mode")
                .font(.headline)

            Text("Enter your PIN to end this work interval early.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            SecureField("PIN", text: $pin)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    submit()
                }

            HStack {
                Button("Cancel") {
                    coordinator.cancelLockedStopPrompt()
                }

                Spacer()

                Button("Unlock & Stop") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(pin.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }

    private func submit() {
        coordinator.stopSessionWithPIN(pin)
        pin = ""
    }
}
