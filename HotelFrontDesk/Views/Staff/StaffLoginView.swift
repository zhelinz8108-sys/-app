import SwiftUI

struct StaffLoginView: View {
    @ObservedObject var staffService: StaffService
    @State private var username = ""
    @State private var password = ""
    @State private var showError = false
    @State private var isLoading = false
    @State private var setupName = ""
    @State private var setupUsername = ""
    @State private var setupPassword = ""
    @State private var setupConfirmPassword = ""
    @State private var setupPhone = ""
    @State private var setupError: String?

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

                    if staffService.requiresInitialManagerSetup {
                        initialSetupForm
                    } else {
                        loginForm
                    }
                    .frame(maxWidth: min(geo.size.width * 0.5, 420))

                    Spacer().frame(height: 24)

                    Spacer()
                    Spacer()
                }
            }
        }
    }

    private var loginForm: some View {
        VStack(spacing: 32) {
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
    }

    private var initialSetupForm: some View {
        VStack(spacing: 20) {
            Text("首次部署，请先创建管理员账号。创建完成后系统会直接进入管理端。")
                .font(.callout)
                .foregroundStyle(.textSecondary)
                .multilineTextAlignment(.center)

            setupInput(icon: "person.text.rectangle", title: "管理员姓名", text: $setupName)
            setupInput(icon: "person", title: "管理员用户名", text: $setupUsername, autocapitalization: false)
            setupInput(icon: "phone", title: "联系电话（选填）", text: $setupPhone, keyboard: .phonePad)
            secureSetupInput(title: "登录密码", text: $setupPassword)
            secureSetupInput(title: "确认密码", text: $setupConfirmPassword)

            if let setupError {
                Text(setupError)
                    .font(.caption)
                    .foregroundStyle(.appError)
            }

            Button {
                createInitialManager()
            } label: {
                Text("初始化管理员")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(isSetupFormValid ? Color.appAccent : Color.textSecondary.opacity(0.3))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(!isSetupFormValid)
        }
    }

    private var isSetupFormValid: Bool {
        !setupName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !setupUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !setupPassword.isEmpty &&
        setupPassword == setupConfirmPassword
    }

    private func setupInput(
        icon: String,
        title: String,
        text: Binding<String>,
        autocapitalization: Bool = true,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(.textSecondary)
                    .frame(width: 24)
                TextField(title, text: text)
                    .font(.title3)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(autocapitalization ? .words : .never)
                    .keyboardType(keyboard)
                    .foregroundStyle(.textPrimary)
            }
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.textSecondary.opacity(0.3))
                .frame(height: 1)
        }
    }

    private func secureSetupInput(title: String, text: Binding<String>) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: "lock")
                    .font(.title3)
                    .foregroundStyle(.textSecondary)
                    .frame(width: 24)
                SecureField(title, text: text)
                    .font(.title3)
                    .foregroundStyle(.textPrimary)
            }
            .padding(.bottom, 14)

            Rectangle()
                .fill(Color.textSecondary.opacity(0.3))
                .frame(height: 1)
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

    private func createInitialManager() {
        setupError = nil
        guard setupPassword == setupConfirmPassword else {
            setupError = "两次输入的密码不一致"
            return
        }

        if let error = staffService.bootstrapInitialManager(
            name: setupName,
            username: setupUsername,
            password: setupPassword,
            phone: setupPhone
        ) {
            setupError = error
            return
        }

        setupName = ""
        setupUsername = ""
        setupPassword = ""
        setupConfirmPassword = ""
        setupPhone = ""
    }
}
