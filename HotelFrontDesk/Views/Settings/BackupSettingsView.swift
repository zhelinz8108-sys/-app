import SwiftUI

/// 备份与恢复设置页
struct BackupSettingsView: View {
    @ObservedObject private var backupService = BackupService.shared
    @ObservedObject private var staffService = StaffService.shared
    @ObservedObject private var cloudKit = CloudKitService.shared
    @State private var iCloudMeta: BackupMeta?
    @State private var showRestoreConfirm = false
    @State private var selectedSnapshot: BackupSnapshot?
    @State private var showExportShare = false
    @State private var exportURL: URL?
    @State private var resultMessage: String?
    @State private var showResult = false
    @State private var isRestoring = false
    @State private var isExportingAI = false

    var body: some View {
        List {
            if let protectionIssue = cloudKit.dataProtectionIssue ?? staffService.credentialIntegrityIssue {
                Section {
                    Label(protectionIssue, systemImage: "shield.lefthalf.filled.badge.exclamationmark")
                        .font(.subheadline)
                        .foregroundStyle(.red)
                } header: {
                    Text("需要恢复处理")
                } footer: {
                    Text("请优先确认目标设备使用同一 Apple ID，并已开启 iCloud Drive 与“密码与钥匙串”。")
                }
            }

            // MARK: - 健康检查
            Section {
                ForEach(backupService.backupHealthItems()) { item in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: item.state.icon)
                            .foregroundStyle(Color(uiColor: item.state.color))
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .fontWeight(.medium)
                            Text(item.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("上线健康检查")
            } footer: {
                Text("正式上线前，建议至少完成一次手动备份，并在同一 Apple ID 的备用设备上验证恢复流程。")
            }

            // MARK: - 自动备份设置
            Section {
                Toggle(isOn: $backupService.autoBackupEnabled) {
                    HStack(spacing: 10) {
                        Image(systemName: "clock.arrow.circlepath")
                            .foregroundStyle(.blue)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("自动备份")
                                .fontWeight(.medium)
                            Text("数据变动后每10分钟自动备份")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Image(systemName: backupService.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(backupService.iCloudAvailable ? .blue : .red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backupService.iCloudAvailable ? "iCloud Drive 已连接" : "iCloud Drive 不可用")
                            .fontWeight(.medium)
                        if !backupService.iCloudAvailable {
                            Text("请在系统设置中登录 iCloud")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }

                if let lastTime = backupService.lastBackupTime {
                    HStack {
                        Text("上次备份")
                        Spacer()
                        Text(formatDateTime(lastTime))
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = backupService.backupError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                // 手动触发备份
                Button {
                    Task {
                        await backupService.performBackup()
                        iCloudMeta = backupService.fetchICloudBackupMeta()
                        resultMessage = backupService.backupError ?? "备份成功"
                        showResult = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        if backupService.isBackingUp {
                            ProgressView().padding(.trailing, 6)
                        }
                        Label("立即备份", systemImage: "arrow.clockwise.icloud")
                        Spacer()
                    }
                }
                .disabled(!staffService.isManager || backupService.isBackingUp)
            } header: {
                Text("iCloud 自动备份")
            } footer: {
                Text(staffService.isManager
                     ? "CloudKit 同步房间和订单到云端，iCloud Drive 备份全量数据文件。保留最近7天每日备份。"
                     : "备份、恢复和导出仅管理员可执行。前台员工可在这里查看当前备份状态。")
            }

            // MARK: - 备份历史列表
            Section {
                if backupService.availableBackups.isEmpty {
                    HStack {
                        Image(systemName: "tray")
                            .foregroundStyle(.secondary)
                        Text("暂无备份记录")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(backupService.availableBackups) { snapshot in
                        backupRow(snapshot)
                    }
                }
            } header: {
                HStack {
                    Text("备份历史")
                    Spacer()
                    Button {
                        backupService.refreshAvailableBackups()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption)
                    }
                }
            } footer: {
                Text("自动保留最近7天的每日备份，更早的自动清理。点击备份可恢复或分享。")
            }

            // MARK: - 手动导出
            Section {
                Button {
                    exportAIAnalysisData()
                } label: {
                    HStack {
                        if isExportingAI {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Label("导出脱敏经营数据包", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                .disabled(!staffService.isManager || isExportingAI)

                Button {
                    exportData()
                } label: {
                    Label("导出数据文件", systemImage: "square.and.arrow.up")
                }
                .disabled(!staffService.isManager || isExportingAI)

                Text("经营数据包会尽量脱敏后再导出，只适合授权的数据分析、表格处理或内部报表使用；如需发送到第三方平台，请先确认符合酒店隐私政策。原始数据导出仍仅用于备份存档。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("手动导出")
            }
        }
        .navigationTitle("备份与恢复")
        .onAppear {
            iCloudMeta = backupService.fetchICloudBackupMeta()
            backupService.refreshAvailableBackups()
        }
        .alert("确认恢复", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {
                selectedSnapshot = nil
            }
            Button("确认恢复", role: .destructive) {
                if let snapshot = selectedSnapshot {
                    Task { await restore(from: snapshot) }
                }
            }
        } message: {
            if let snapshot = selectedSnapshot {
                Text("从备份「\(snapshot.displayDate)」恢复将覆盖当前所有数据，此操作不可撤销。\n恢复后需要重启 app。")
            } else {
                Text("从备份恢复将覆盖当前所有数据，此操作不可撤销。")
            }
        }
        .alert("结果", isPresented: $showResult) {
            Button("确定") {}
        } message: {
            Text(resultMessage ?? "")
        }
        .sheet(isPresented: $showExportShare) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - 备份行

    private func backupRow(_ snapshot: BackupSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: snapshot.isCloud ? "icloud.fill" : "internaldrive")
                    .foregroundStyle(snapshot.isCloud ? .blue : .gray)
                    .font(.caption)
                VStack(alignment: .leading, spacing: 2) {
                    Text(snapshot.displayDate)
                        .fontWeight(.medium)
                    HStack(spacing: 12) {
                        Text(snapshot.displaySize)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let meta = snapshot.meta {
                            Label("\(meta.fileCount)个文件", systemImage: "doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label(meta.deviceName, systemImage: "ipad")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                Spacer()
            }

            if staffService.isManager {
                HStack(spacing: 12) {
                    Button {
                        selectedSnapshot = snapshot
                        showRestoreConfirm = true
                    } label: {
                        Label("恢复", systemImage: "arrow.down.circle")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.orange)
                    .buttonStyle(.borderless)

                    Button {
                        shareSnapshot(snapshot)
                    } label: {
                        Label("分享", systemImage: "square.and.arrow.up")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.blue)
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 操作方法

    private func restore(from snapshot: BackupSnapshot) async {
        isRestoring = true
        let success = await backupService.restoreFromBackup(snapshot)
        isRestoring = false
        selectedSnapshot = nil
        backupService.refreshAvailableBackups()
        iCloudMeta = backupService.fetchICloudBackupMeta()
        resultMessage = success ? "恢复成功，请重启 app 加载新数据" : (backupService.backupError ?? "恢复失败")
        showResult = true
    }

    private func exportData() {
        do {
            exportURL = try backupService.exportBackup()
            showExportShare = true
        } catch {
            resultMessage = "导出失败: \(error.localizedDescription)"
            showResult = true
        }
    }

    private func shareSnapshot(_ snapshot: BackupSnapshot) {
        do {
            exportURL = try backupService.exportSnapshot(snapshot)
            showExportShare = true
        } catch {
            resultMessage = "导出备份失败: \(error.localizedDescription)"
            showResult = true
        }
    }

    private func exportAIAnalysisData() {
        isExportingAI = true
        Task {
            do {
                let url = try await backupService.exportDataPackage()
                exportURL = url
                showExportShare = true
            } catch {
                resultMessage = "导出经营数据包失败: \(error.localizedDescription)"
                showResult = true
            }
            isExportingAI = false
        }
    }

    private func formatDateTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }
}
