import SwiftUI

/// Shown after the user taps the password-reset link in their email.
/// The recovery session is already established by the time this appears,
/// so submitting simply updates the password on the current user.
struct ResetPasswordView: View {
    @Environment(ThemeManager.self) private var themeManager

    @State private var newPassword: String = ""
    @State private var confirmPassword: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var didSucceed: Bool = false

    let supabase = SupabaseService.shared
    /// Called when the flow is finished (success or cancel) to dismiss.
    var onFinished: () -> Void

    private var passwordsValid: Bool {
        newPassword.count >= 6 && newPassword == confirmPassword
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    formSection
                    actionButton
                    cancelButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 60)
                .padding(.bottom, 40)
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK") {}
        } message: {
            Text(errorMessage ?? "Something went wrong.")
        }
        .alert("Password Updated", isPresented: $didSucceed) {
            Button("OK") { onFinished() }
        } message: {
            Text("Your password has been changed. You can now sign in with your new password.")
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 260)

            Text("Set a new password")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var formSection: some View {
        VStack(spacing: 16) {
            AuthSecureField(
                icon: "lock.fill",
                placeholder: "New Password",
                text: $newPassword,
                color: themeManager.currentTheme.primary
            )

            AuthSecureField(
                icon: "lock.rotation",
                placeholder: "Confirm Password",
                text: $confirmPassword,
                color: themeManager.currentTheme.primary
            )

            if !newPassword.isEmpty && newPassword.count < 6 {
                Text("Password must be at least 6 characters.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else if !confirmPassword.isEmpty && newPassword != confirmPassword {
                Text("Passwords don't match.")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var actionButton: some View {
        Button {
            Task { await submit() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().tint(.white)
                }
                Text("Update Password")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(themeManager.currentTheme.primary)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 14))
        }
        .disabled(isLoading || !passwordsValid)
        .opacity(isLoading || !passwordsValid ? 0.6 : 1)
    }

    private var cancelButton: some View {
        Button {
            onFinished()
        } label: {
            Text("Cancel")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func submit() async {
        isLoading = true
        defer { isLoading = false }
        do {
            try await supabase.updatePassword(newPassword)
            didSucceed = true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}
