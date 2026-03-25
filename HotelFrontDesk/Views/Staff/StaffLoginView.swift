import SwiftUI

struct StaffLoginView: View {
    @ObservedObject var staffService: StaffService
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false
    @State private var isLoading = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 背景
                Color.appBackground
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    Spacer()

                    // Logo
                    VStack(spacing: 20) {
                        Image(systemName: "building.columns.fill")
                            .font(.system(size: 64, weight: .light))
                            .foregroundStyle(.appPrimary)

                        Text(L("dashboard.title"))
                            .font(.system(size: 36, weight: .semibold))
                            .foregroundStyle(.textPrimary)

                        Text(L("login.title"))
                            .font(.title3)
                            .foregroundStyle(.textSecondary)
                    }

                    Spacer().frame(height: 56)

                    // 登录表单
                    VStack(spacing: 32) {
                        // Username field
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Image(systemName: "person")
                                    .font(.title3)
                                    .foregroundStyle(.textSecondary)
                                    .frame(width: 24)
                                TextField(L("login.username"), text: $username)
                                    .font(.title3)
                                    .textContentType(.username)
                                    .autocorrectionDisabled()
                                    .textInputAutocapitalization(.never)
                                    .foregroundStyle(.textPrimary)
                            }
                            .padding(.bottom, 14)

                            Rectangle()
                                .fill(Color.textSecondary.opacity(0.3))
                                .frame(height: 1)
                        }

                        // Password field
                        VStack(spacing: 0) {
                            HStack(spacing: 14) {
                                Image(systemName: "lock")
                                    .font(.title3)
                                    .foregroundStyle(.textSecondary)
                                    .frame(width: 24)
                                SecureField(L("login.password"), text: $password)
                                    .font(.title3)
                                    .textContentType(.password)
                                    .foregroundStyle(.textPrimary)
                            }
                            .padding(.bottom, 14)

                            Rectangle()
                                .fill(Color.textSecondary.opacity(0.3))
                                .frame(height: 1)
                        }

                        // Error messages
                        if let issue = staffService.credentialIntegrityIssue {
                            Text(issue)
                                .font(.caption)
                                .foregroundStyle(.appError)
                        } else if staffService.isLockedOut(username: username) {
                            HStack(spacing: 6) {
                                Image(systemName: "lock.fill")
                                Text("登录已锁定，请 \(staffService.lockoutRemainingSeconds(for: username) / 60 + 1) 分钟后重试")
                            }
                            .font(.caption)
                            .foregroundStyle(.appError)
                        } else if showError {
                            Text(L("login.error"))
                                .font(.caption)
                                .foregroundStyle(.appError)
                        }

                        // Gold accent button
                        Button {
                            attemptLogin()
                        } label: {
                            HStack(spacing: 8) {
                                if isLoading {
                                    ProgressView()
                                        .tint(.white)
                                }
                                Text(L("login.submit"))
                                    .font(.title3)
                                    .fontWeight(.semibold)
                                    .tracking(2)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 18)
                            .background(
                                username.isEmpty || password.isEmpty
                                    ? Color.textSecondary.opacity(0.3)
                                    : Color.appAccent
                            )
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .disabled(username.isEmpty || password.isEmpty)
                    }
                    .frame(maxWidth: min(geo.size.width * 0.5, 420))

                    Spacer().frame(height: 24)

                    Spacer()
                    Spacer()
                }
            }
        }
    }

    private func attemptLogin() {
        showError = false
        isLoading = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            let success = staffService.login(username: username, password: password)
            isLoading = false
            if !success {
                showError = true
                password = ""
            }
        }
    }
}
