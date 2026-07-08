//
//  LoginView.swift
//  Budgetty
//
//  Email/password sign-in & sign-up (same account model as Android — no anonymous / third-party
//  sign-in, so accounts are identical across platforms). Shown until a user is signed in.
//

import SwiftUI

struct LoginView: View {
    @Environment(AuthModel.self) private var auth

    @State private var isSignUp = false
    @State private var email = ""
    @State private var password = ""
    @State private var busy = false
    @State private var errorMessage: String?
    @State private var showReset = false
    @State private var resetEmail = ""
    @State private var resetSent = false

    private var strength: PasswordStrength { PasswordStrength.of(password) }
    private var canSubmit: Bool {
        !busy && email.contains("@") && password.count >= 6
        && (!isSignUp || strength != .weak)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                Picker("", selection: $isSignUp) {
                    Text("Sign In").tag(false)
                    Text("Sign Up").tag(true)
                }
                .pickerStyle(.segmented)
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
                        else { Text(isSignUp ? "Create Account" : "Sign In").fontWeight(.semibold) }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 50)
                    .background(Palette.tint.opacity(canSubmit ? 1 : 0.5),
                                in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .disabled(!canSubmit)
                .padding(.top, 20)

                HStack(spacing: 4) {
                    Text(isSignUp ? "Already have an account?" : "Don't have an account?")
                        .foregroundStyle(Palette.secondaryLabel)
                    Button(isSignUp ? "Sign In" : "Sign Up") { withAnimation { isSignUp.toggle() } }
                        .fontWeight(.semibold).foregroundStyle(Palette.tint)
                }
                .font(.subheadline).padding(.top, 24)
            }
            .padding(.horizontal, 20).padding(.bottom, 40)
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
            }
            .padding(.horizontal, 16).frame(height: 46)
            Divider().padding(.leading, 16)
            HStack {
                Text("Password").foregroundStyle(Palette.secondaryLabel).frame(width: 90, alignment: .leading)
                SecureField("••••••••", text: $password)
                    .textContentType(isSignUp ? .newPassword : .password)
            }
            .padding(.horizontal, 16).frame(height: 46)
        }
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
