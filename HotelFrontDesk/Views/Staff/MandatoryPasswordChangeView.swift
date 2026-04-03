import SwiftUI

struct MandatoryPasswordChangeView: View {
    @ObservedObject private var staffService = StaffService.shared
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var errorMessage: String?

    private let logService = OperationLogService.shared

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(staffService.mandatoryPasswordChangeMessage)
                        .font(.body)
                } header: {
                    Text("必须先改密")
                }

                Section("当前账号") {
                    LabeledContent("姓名", value: staffService.currentStaff?.name ?? "-")
                    LabeledContent("用户名", value: staffService.currentStaff?.username ?? "-")
                }

                Section("新密码") {
                    SecureField("至少8位，包含字母和数字", text: $newPassword)
                    SecureField("再次输入新密码", text: $confirmPassword)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }

                Section {
                    Button("更新密码") {
                        submit()
                    }
                    .disabled(newPassword.isEmpty || confirmPassword.isEmpty)

                    Button("退出登录", role: .destructive) {
                        staffService.logout()
                    }
                }
            }
            .navigationTitle("安全改密")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func submit() {
        guard let staff = staffService.currentStaff else { return }
        guard newPassword == confirmPassword else {
            errorMessage = "两次输入的密码不一致"
            return
        }
        if let error = staffService.passwordPolicyError(for: newPassword) {
            errorMessage = error
            return
        }

        staffService.changePassword(staffID: staff.id, newPassword: newPassword)
        logService.log(
            type: .passwordChange,
            summary: "\(staff.name) 完成首次改密",
            detail: "账号 \(staff.username) 在强制安全校验页完成密码更新"
        )
        errorMessage = nil
        newPassword = ""
        confirmPassword = ""
    }
}
