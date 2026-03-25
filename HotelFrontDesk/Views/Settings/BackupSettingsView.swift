import SwiftUI

/// 备份与恢复设置页
struct BackupSettingsView: View {
    @ObservedObject private var backupService = BackupService.shared
    @ObservedObject private var staffService = StaffService.shared
    @ObservedObject private var cloudKit = CloudKitService.shared
    @State private var iCloudMeta: BackupMeta?
    @State private var showRestoreConfirm = false
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

            // iCloud 自动备份状态
            Section {
                HStack {
                    Image(systemName: backupService.iCloudAvailable ? "icloud.fill" : "icloud.slash")
                        .foregroundStyle(backupService.iCloudAvailable ? .blue : .red)
                        .font(.title3)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(backupService.iCloudAvailable ? "iCloud Drive 已连接" : "iCloud Drive 不可用")
                            .fontWeight(.medium)
                        if backupService.iCloudAvailable {
                            Text("数据每10分钟自动备份到 iCloud Drive")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
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
                        resultMessage = backupService.backupError ?? "✅ 备份成功"
                        showResult = true
                    }
                } label: {
                    HStack {
                        Spacer()
                        if backupService.isBackingUp {
                            ProgressView().padding(.trailing, 6)
                        }
                        Label("立即备份到 iCloud", systemImage: "arrow.clockwise.icloud")
                        Spacer()
                    }
                }
                .disabled(!staffService.isManager || !backupService.iCloudAvailable || backupService.isBackingUp)
            } header: {
                Text("iCloud 自动备份")
            } footer: {
                Text(staffService.isManager
                     ? "CloudKit 同步房间和订单到云端，iCloud Drive 备份全量数据文件。双重保险。"
                     : "备份、恢复和导出仅管理员可执行。前台员工可在这里查看当前备份状态。")
            }

            // iCloud 恢复
            Section {
                if let meta = iCloudMeta {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("云端备份")
                                .fontWeight(.medium)
                            Spacer()
                            Text(formatDateTime(meta.timestamp))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        HStack(spacing: 16) {
                            Label(meta.deviceName, systemImage: "ipad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("v\(meta.appVersion)", systemImage: "app.badge")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Label("\(meta.fileCount)个文件", systemImage: "doc")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let includedFiles = meta.includedFiles, !includedFiles.isEmpty {
                            Text("包含: \(includedFiles.joined(separator: "、"))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if meta.receiptsIncluded == true {
                            Label("已包含小票照片目录", systemImage: "photo.on.rectangle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showRestoreConfirm = true
                    } label: {
                        HStack {
                            Spacer()
                            Label("从 iCloud 恢复数据", systemImage: "arrow.down.circle")
                            Spacer()
                        }
                    }
                    .foregroundStyle(.orange)
                    .disabled(!staffService.isManager)
                } else {
                    HStack {
                        Image(systemName: "icloud.slash")
                            .foregroundStyle(.secondary)
                        Text("iCloud 中没有备份")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("从 iCloud 恢复")
            } footer: {
                Text("恢复会覆盖当前设备上的所有数据。适用于新 iPad 或数据丢失后恢复。")
            }

            // 手动导出
            Section {
                Button {
                    exportAIAnalysisData()
                } label: {
                    HStack {
                        if isExportingAI {
                            ProgressView()
                                .padding(.trailing, 4)
                        }
                        Label("导出经营数据包", systemImage: "square.and.arrow.up.on.square")
                    }
                }
                .disabled(!staffService.isManager || isExportingAI)

                Button {
                    exportData()
                } label: {
                    Label("导出数据文件", systemImage: "square.and.arrow.up")
                }
                .disabled(!staffService.isManager || isExportingAI)

                Text("经营数据包只导出纯数据，包含房间、客人、入住、押金、OTA 来源和收益汇总的 JSON/CSV，可直接上传给 ChatGPT、Gemini 或表格工具。原始数据导出仍保留给备份存档使用。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("手动导出")
            }
        }
        .navigationTitle("备份与恢复")
        .onAppear {
            iCloudMeta = backupService.fetchICloudBackupMeta()
        }
        .alert("确认恢复", isPresented: $showRestoreConfirm) {
            Button("取消", role: .cancel) {}
            Button("确认恢复", role: .destructive) {
                Task { await restore() }
            }
        } message: {
            Text("从 iCloud 恢复将覆盖当前所有数据，此操作不可撤销。\n恢复后需要重启 app。")
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

    private func restore() async {
        isRestoring = true
        let success = await backupService.restoreFromICloud()
        isRestoring = false
        iCloudMeta = backupService.fetchICloudBackupMeta()
        resultMessage = success ? "✅ 恢复成功，请重启 app 加载新数据" : (backupService.backupError ?? "恢复失败")
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
