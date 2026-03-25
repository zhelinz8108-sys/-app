import SwiftUI

struct StaffManageView: View {
    @ObservedObject private var staffService = StaffService.shared
    @State private var staffList: [Staff] = []
    @State private var showAddStaff = false
    @State private var editingStaff: Staff?
    @State private var showResetPassword = false
    @State private var resetPasswordStaff: Staff?
    @State private var newPasswordInput = ""
    @State private var resultMessage: String?
    @State private var showResult = false

    // 新增/编辑表单
    @State private var formName = ""
    @State private var formUsername = ""
    @State private var formPassword = ""
    @State private var formRole: StaffRole = .employee
    @State private var formPhone = ""

    private let logService = OperationLogService.shared

    private func maskedPhoneForLog(_ phone: String) -> String {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return "" }
        let masked = Validators.maskedPhone(trimmed)
        return masked != trimmed ? masked : Validators.maskedSensitive(trimmed)
    }

    var body: some View {
        List {
            // 当前登录信息
            Section {
                HStack {
                    Image(systemName: "person.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(staffService.currentName)
                            .font(.headline)
                        Text(staffService.currentStaff?.role.rawValue ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("退出登录") {
                        staffService.logout()
                    }
                    .foregroundStyle(.red)
                    .font(.callout)
                }
            } header: {
                Text("当前账号")
            }

            // 员工列表
            Section {
                if staffList.isEmpty {
                    Text("暂无员工").foregroundStyle(.secondary)
                } else {
                    ForEach(staffList) { staff in
                        staffRow(staff)
                    }
                }
            } header: {
                HStack {
                    Text("所有账号 (\(staffList.count))")
                    Spacer()
                    Button {
                        resetForm()
                        editingStaff = nil
                        showAddStaff = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                }
            }
        }
        .navigationTitle("员工管理")
        .onAppear { staffList = staffService.fetchAll() }
        .sheet(isPresented: $showAddStaff, onDismiss: { staffList = staffService.fetchAll() }) {
            staffFormSheet
        }
        .alert("结果", isPresented: $showResult) {
            Button("确定") {}
        } message: {
            Text(resultMessage ?? "")
        }
        .alert("重置密码", isPresented: $showResetPassword) {
            SecureField("新密码（至少8位，字母+数字）", text: $newPasswordInput)
            Button("取消", role: .cancel) {}
            Button("确定") {
                guard let staff = resetPasswordStaff else { return }
                if let error = staffService.passwordPolicyError(for: newPasswordInput) {
                    resultMessage = error
                    showResult = true
                } else {
                    staffService.changePassword(staffID: staff.id, newPassword: newPasswordInput)
                    logService.log(
                        type: .passwordChange,
                        summary: "重置 \(staff.name) 的密码",
                        detail: "管理员重置了 \(staff.name)(\(staff.username)) 的登录密码"
                    )
                    resultMessage = "✅ \(staff.name) 的密码已重置"
                    showResult = true
                    staffList = staffService.fetchAll()
                }
                newPasswordInput = ""
            }
        } message: {
            if let staff = resetPasswordStaff {
                Text("为 \(staff.name)(\(staff.username)) 设置新密码")
            }
        }
    }

    // MARK: - 员工行

    private func staffRow(_ staff: Staff) -> some View {
        HStack(spacing: 12) {
            // 头像
            Image(systemName: staff.role == .manager ? "person.badge.key.fill" : "person.fill")
                .font(.title3)
                .foregroundStyle(staff.isActive ? (staff.role == .manager ? .orange : .blue) : .gray)
                .frame(width: 30)

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(staff.name)
                        .fontWeight(.medium)
                    Text(staff.role.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(staff.role == .manager ? Color.orange.opacity(0.15) : Color.blue.opacity(0.15))
                        .clipShape(Capsule())
                    if !staff.isActive {
                        Text("已停用")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
                            .clipShape(Capsule())
                    }
                    if staff.id == staffService.currentStaff?.id {
                        Text("当前")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }
                Text("用户名: \(staff.username)\(staff.phone.isEmpty ? "" : " | 电话: \(staff.phone)")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 2)
        .opacity(staff.isActive ? 1 : 0.6)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            if staff.id != staffService.currentStaff?.id {
                Button(role: .destructive) {
                    staffService.deleteStaff(id: staff.id)
                    logService.log(
                        type: .dataReset,
                        summary: "删除员工 \(staff.name)",
                        detail: "删除员工: \(staff.name)(\(staff.username)) | 角色: \(staff.role.rawValue)"
                    )
                    staffList = staffService.fetchAll()
                } label: {
                    Label("删除", systemImage: "trash")
                }

                Button {
                    staffService.toggleActive(id: staff.id)
                    staffList = staffService.fetchAll()
                } label: {
                    Label(staff.isActive ? "停用" : "启用",
                          systemImage: staff.isActive ? "person.slash" : "person.badge.plus")
                }
                .tint(staff.isActive ? .orange : .green)
            }

            Button {
                resetPasswordStaff = staff
                newPasswordInput = ""
                showResetPassword = true
            } label: {
                Label("重置密码", systemImage: "key")
            }
            .tint(.purple)

            Button {
                startEditing(staff)
            } label: {
                Label("编辑", systemImage: "pencil")
            }
            .tint(.blue)
        }
    }

    // MARK: - 新增/编辑表单

    private var staffFormSheet: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("姓名")
                        Spacer()
                        TextField("如 张三", text: $formName)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("电话")
                        Spacer()
                        TextField("选填", text: $formPhone)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.phonePad)
                    }
                }

                Section("登录信息") {
                    HStack {
                        Text("用户名")
                        Spacer()
                        TextField("登录用", text: $formUsername)
                            .multilineTextAlignment(.trailing)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    if editingStaff == nil {
                        HStack {
                            Text("初始密码")
                            Spacer()
                            SecureField("至少8位，字母+数字", text: $formPassword)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section("角色") {
                    Picker("角色", selection: $formRole) {
                        ForEach(StaffRole.allCases) { role in
                            Text(role.rawValue).tag(role)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                if formRole == .manager {
                    Section {
                        Label("管理员可查看数据分析、操作日志、员工管理，可增删房间", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Label("前台员工可办理入住/退房、查看房态，不能增删房间或查看经营数据", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(editingStaff != nil ? "编辑员工" : "添加员工")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showAddStaff = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editingStaff != nil ? "保存" : "添加") {
                        saveStaff()
                    }
                    .fontWeight(.bold)
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private var isFormValid: Bool {
        let nameOK = !formName.trimmingCharacters(in: .whitespaces).isEmpty
        let usernameOK = !formUsername.trimmingCharacters(in: .whitespaces).isEmpty
        let passwordOK = editingStaff != nil || staffService.passwordPolicyError(for: formPassword) == nil
        return nameOK && usernameOK && passwordOK
    }

    private func saveStaff() {
        let trimmedUsername = formUsername.trimmingCharacters(in: .whitespaces)

        if staffService.isUsernameTaken(trimmedUsername, excludingID: editingStaff?.id) {
            resultMessage = "用户名 \(trimmedUsername) 已被使用"
            showResult = true
            return
        }

        if editingStaff == nil, let error = staffService.passwordPolicyError(for: formPassword) {
            resultMessage = error
            showResult = true
            return
        }

        if let editing = editingStaff {
            var updated = editing
            updated.name = formName.trimmingCharacters(in: .whitespaces)
            updated.username = trimmedUsername
            updated.role = formRole
            updated.phone = formPhone.trimmingCharacters(in: .whitespaces)
            staffService.updateStaff(updated)
            logService.log(
                type: .roomEdit,
                summary: "编辑员工 \(updated.name)",
                detail: "姓名: \(updated.name) | 用户名: \(updated.username) | 角色: \(updated.role.rawValue)\(updated.phone.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " | 电话: \(maskedPhoneForLog(updated.phone))")"
            )
        } else {
            let newStaff = Staff(
                name: formName.trimmingCharacters(in: .whitespaces),
                username: trimmedUsername,
                password: formPassword,
                role: formRole,
                phone: formPhone.trimmingCharacters(in: .whitespaces)
            )
            staffService.addStaff(newStaff)
            logService.log(
                type: .roomAdd,
                summary: "新增员工 \(newStaff.name)",
                detail: "姓名: \(newStaff.name) | 用户名: \(newStaff.username) | 角色: \(newStaff.role.rawValue)\(newStaff.phone.trimmingCharacters(in: .whitespaces).isEmpty ? "" : " | 电话: \(maskedPhoneForLog(newStaff.phone))")"
            )
        }

        showAddStaff = false
    }

    private func startEditing(_ staff: Staff) {
        editingStaff = staff
        formName = staff.name
        formUsername = staff.username
        formPassword = ""
        formRole = staff.role
        formPhone = staff.phone
        showAddStaff = true
    }

    private func resetForm() {
        formName = ""
        formUsername = ""
        formPassword = ""
        formRole = .employee
        formPhone = ""
    }
}
