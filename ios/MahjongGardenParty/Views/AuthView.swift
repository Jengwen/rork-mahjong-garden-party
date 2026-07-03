import SwiftUI

struct AuthView: View {
    @Environment(ThemeManager.self) private var themeManager
    @State private var isSignUp: Bool = false
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var displayName: String = ""
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var showError: Bool = false
    @State private var showForgotPassword: Bool = false
    @State private var resetEmail: String = ""
    @State private var resetSent: Bool = false
    @State private var resetError: String?

    let supabase = SupabaseService.shared
    var onAuthenticated: () -> Void

    var body: some View {
        ZStack {
            gardenBackground.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 32) {
                    headerSection
                    formSection
                    if !isSignUp {
                        forgotPasswordButton
                    }
                    actionButton
                    toggleSection
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
        .alert("Reset Password", isPresented: $showForgotPassword) {
            TextField("Email", text: $resetEmail)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
            Button("Send Reset Link") {
                Task { await sendReset() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter your email address and we'll send you a link to reset your password.")
        }
        .alert("Check Your Email", isPresented: $resetSent) {
            Button("OK") {}
        } message: {
            Text("A password reset link has been sent to \(resetEmail).")
        }
        .alert("Reset Failed", isPresented: .init(
            get: { resetError != nil },
            set: { if !$0 { resetError = nil } }
        )) {
            Button("OK") { resetError = nil }
        } message: {
            Text(resetError ?? "")
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image("logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 260)

            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var formSection: some View {
        VStack(spacing: 16) {
            if isSignUp {
                AuthTextField(
                    icon: "person.fill",
                    placeholder: "Display Name",
                    text: $displayName,
                    color: themeManager.currentTheme.primary
                )
            }

            AuthTextField(
                icon: "envelope.fill",
                placeholder: "Email",
                text: $email,
                color: themeManager.currentTheme.primary,
                keyboardType: .emailAddress,
                autocapitalization: .never
            )

            AuthSecureField(
                icon: "lock.fill",
                placeholder: "Password",
                text: $password,
                color: themeManager.currentTheme.primary
            )
        }
    }

    private var actionButton: some View {
        Button {
            Task { await authenticate() }
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(.white)
                }
                Text(isSignUp ? "Create Account" : "Sign In")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(themeManager.currentTheme.primary)
            .foregroundStyle(.white)
            .clipShape(.rect(cornerRadius: 14))
        }
        .disabled(isLoading || email.isEmpty || password.isEmpty || (isSignUp && displayName.isEmpty))
        .opacity(isLoading || email.isEmpty || password.isEmpty || (isSignUp && displayName.isEmpty) ? 0.6 : 1)
    }

    private var toggleSection: some View {
        Button {
            withAnimation(.snappy) {
                isSignUp.toggle()
                errorMessage = nil
            }
        } label: {
            HStack(spacing: 4) {
                Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                    .foregroundStyle(.secondary)
                Text(isSignUp ? "Sign In" : "Sign Up")
                    .fontWeight(.semibold)
                    .foregroundStyle(themeManager.currentTheme.primary)
            }
            .font(.subheadline)
        }
    }

    private var gardenBackground: some View {
        Color.white
    }

    private var forgotPasswordButton: some View {
        Button {
            resetEmail = email
            showForgotPassword = true
        } label: {
            Text("Forgot Password?")
                .font(.subheadline)
                .foregroundStyle(themeManager.currentTheme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func sendReset() async {
        guard !resetEmail.isEmpty else {
            resetError = "Please enter an email address."
            return
        }
        do {
            try await supabase.resetPassword(for: resetEmail)
            resetSent = true
        } catch {
            resetError = error.localizedDescription
        }
    }

    private func authenticate() async {
        isLoading = true
        defer { isLoading = false }

        do {
            if isSignUp {
                try await supabase.signUpWithEmail(email, password: password, displayName: displayName)
            } else {
                try await supabase.signInWithEmail(email, password: password)
            }
            onAuthenticated()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }
}

struct AuthTextField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let color: Color
    var keyboardType: UIKeyboardType = .default
    var autocapitalization: TextInputAutocapitalization = .sentences

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 20)

            TextField(placeholder, text: $text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }
}

struct AuthSecureField: View {
    let icon: String
    let placeholder: String
    @Binding var text: String
    let color: Color
    @State private var isVisible: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color.opacity(0.7))
                .frame(width: 20)

            if isVisible {
                TextField(placeholder, text: $text)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            } else {
                SecureField(placeholder, text: $text)
            }

            Button {
                isVisible.toggle()
            } label: {
                Image(systemName: isVisible ? "eye.slash.fill" : "eye.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.ultraThinMaterial)
        .clipShape(.rect(cornerRadius: 12))
    }
}
