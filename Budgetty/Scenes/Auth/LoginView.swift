//
//  LoginView.swift
//  Budgetty
//
//  Email/password sign-in & sign-up plus Sign in with Apple (no anonymous sessions, matching
//  Android). Shown until a user is signed in.
//

import AuthenticationServices
import SwiftUI

struct LoginView: View {
    @Environment(AuthModel.self) private var auth
    @Environment(\.colorScheme) private var colorScheme

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showReset = false
    @State private var resetEmail = ""
    @State private var resetSent = false

    private var orDivider: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Palette.separator).frame(height: 0.5)
            Text("or").font(.footnote).foregroundStyle(Palette.secondaryLabel)
            Rectangle().fill(Palette.separator).frame(height: 0.5)
        }
    }

    /// Human copy for an Apple authorisation failure, or nil when there is nothing worth saying.
    ///
    /// `ASAuthorizationError` surfaces as a bare NSError whose `localizedDescription` is the useless
    /// "The operation couldn't be completed. (…AuthorizationError error 1000.)" — which is exactly
    /// what a device with no Apple Account signed in returns, so it is the message a tester is most
    /// likely to hit.
    private static func appleFailureMessage(_ error: Error) -> String? {
        guard let authError = error as? ASAuthorizationError else { return error.localizedDescription }
        switch authError.code {
        case .canceled:
            return nil // the user backed out; not worth shouting about
        case .unknown, .notInteractive:
            return "Couldn't continue with Apple. Check that you're signed in to your Apple Account "
                 + "in Settings, then try again."
        case .invalidResponse, .notHandled, .failed:
            return "Apple sign-in didn't complete. Please try again."
        @unknown default:
            return "Apple sign-in didn't complete. Please try again."
        }
    }

    /// Apple hands back a result on the main actor; the Firebase exchange is the async half.
    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            errorMessage = Self.appleFailureMessage(error)
        case .success(let authorization):
            busy = true
            Task {
                defer { busy = false }
                do { try await auth.signInWithApple(authorization) }
                catch { errorMessage = error.localizedDescription }
            }
        }
    }

    private var strength: PasswordStrength { PasswordStrength.of(password) }
    private var canSubmit: Bool {
        !busy && email.contains("@") && password.count >= 6
        && (!isSignUp || strength != .weak)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                modeToggle
                    .padding(.bottom, 20)

                fields

                if isSignUp { strengthMeter.padding(.top, 8) }
                if !isSignUp {
                    HStack {
                        Spacer()
                        Button("Forgot Password?") { resetEmail = email; showReset = true }
                            .font(.subheadline).foregroundStyle(Palette.tint)
                    }
                    .padding(.top, 8)
                }

                if let errorMessage {
                    Text(errorMessage).font(.footnote).foregroundStyle(Palette.bad)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 10)
                }

                Button(action: submit) {
                    ZStack {
                        if busy { ProgressView().tint(.white) }
                        else { Text(isSignUp ? "Create account" : "Sign in").font(.headline) }
                    }
                    .ctaPill()
                    .opacity(canSubmit ? 1 : 0.5)
                }
                .disabled(!canSubmit)
                .accessibilityIdentifier(A11y.Login.signIn)
                .padding(.top, 20)

                orDivider
                    .padding(.top, 20)

                // Apple's own button: HIG requires the system control, so it is deliberately not
                // restyled to match `ctaPill()` — only sized to line up with it.
                SignInWithAppleButton(.continue) { request in
                    errorMessage = nil
                    auth.prepareAppleRequest(request)
                } onCompletion: { result in
                    handleApple(result)
                }
                // HIG: white on dark, black on light — a white button on the light canvas reads as
                // a barely-there outline.
                .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                // The style is baked in when the button is made, so flipping appearance while this
                // screen is up leaves the old one until something forces a rebuild.
                .id(colorScheme)
                .frame(height: 52)
                .clipShape(Capsule())
                .disabled(busy)
                .accessibilityIdentifier(A11y.Login.apple)
                .padding(.top, 12)

                HStack(spacing: 4) {
                    Text(isSignUp ? "Have an account?" : "Don't have an account?")
                        .foregroundStyle(Palette.secondaryLabel)
                    Button(isSignUp ? "Sign in" : "Sign Up") { withAnimation { isSignUp.toggle() } }
                        .fontWeight(.semibold).foregroundStyle(Palette.tint)
                }
                .font(.subheadline).padding(.top, 24)
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
            .adaptiveReadableWidth(460)
        }
        .background(Palette.groupedBackground.ignoresSafeArea())
        .alert("Reset password", isPresented: $showReset) {
            TextField("Email", text: $resetEmail)
                .textInputAutocapitalization(.never).keyboardType(.emailAddress)
            Button("Send link") { sendReset() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("We'll email you a link to reset your password.")
        }
        .alert("Check your email", isPresented: $resetSent) {
            Button("OK") {}
        } message: { Text("A password reset link is on its way.") }
    }

    /// Sign In | Sign Up as the shared Liquid Glass pill toggle (mockup), not the system picker.
    private struct Mode: Identifiable, Equatable {
        let signUp: Bool
        var id: Bool { signUp }
    }
    private var modeToggle: some View {
        GlassSegmentedControl(
            options: [Mode(signUp: false), Mode(signUp: true)],
            selection: Binding(get: { Mode(signUp: isSignUp) },
                               set: { isSignUp = $0.signUp })
        ) { $0.signUp ? "Sign Up" : "Sign in" }
        .accessibilityIdentifier(A11y.Login.modeToggle)
    }

    private var header: some View {
        VStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Palette.heroGradient)
                .frame(width: 80, height: 80)
                .overlay(Image(systemName: "doc.text.fill").font(.system(size: 34)).foregroundStyle(.white))
                .shadow(color: Palette.tint.opacity(0.4), radius: 14, y: 8)
            Text("Budgetty").font(.system(size: 34, weight: .bold))
            Text(isSignUp ? "Create your account" : "Welcome back")
                .font(.body).foregroundStyle(Palette.secondaryLabel)
        }
        .padding(.top, 28).padding(.bottom, 24)
    }

    private var fields: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Email").foregroundStyle(Palette.secondaryLabel).frame(width: 90, alignment: .leading)
                TextField("you@example.com", text: $email)
                    .textInputAutocapitalization(.never).keyboardType(.emailAddress)
                    .textContentType(.emailAddress).autocorrectionDisabled()
                    .accessibilityIdentifier(A11y.Login.email)
            }
            .padding(.horizontal, 16).frame(height: 46)
            Divider().padding(.leading, 16)
            HStack {
                Text("Password").foregroundStyle(Palette.secondaryLabel).frame(width: 90, alignment: .leading)
                SecureField("••••••••", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
                    .accessibilityIdentifier(A11y.Login.password)
            }
            .padding(.horizontal, 16).frame(height: 46)
        }
        .inputField(cornerRadius: 12)
    }

    private var strengthMeter: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 3) {
                ForEach(0..<4, id: \.self) { i in
                    Capsule().fill(i < strength.bars ? strength.color : Palette.fill).frame(height: 3)
                }
            }
            Text(strength.label).font(.footnote).foregroundStyle(strength.color)
        }
    }

    private func submit() {
        busy = true; errorMessage = nil
        Task {
            do {
                if isSignUp { try await auth.signUp(email: email, password: password) }
                else { try await auth.signIn(email: email, password: password) }
                // Auth state listener flips the gate to RootView.
            } catch {
                errorMessage = error.localizedDescription
            }
            busy = false
        }
    }

    private func sendReset() {
        Task {
            try? await auth.sendPasswordReset(email: resetEmail)
            resetSent = true
        }
    }
}
