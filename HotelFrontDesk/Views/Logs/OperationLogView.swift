import SwiftUI

struct OperationLogView: View {
    @State private var logs: [OperationLog] = []
    @State private var selectedType: OperationType?
    @State private var searchText = ""
    @State private var exportURL: URL?
    @State private var showExportShare = false
    @State private var resultMessage: String?
    @State private var showResult = false

    private let logService = OperationLogService.shared
    private let typeFilters: [OperationType] = [
        .checkIn, .checkOut, .roomStatusChange,
        .roomAdd, .roomEdit, .roomDelete,
        .depositCollect, .depositRefund,
        .passwordChange, .dataReset, .testDataGenerate
    ]

    private let colorMap: [String: Color] = [
        "green": .green, "blue": .blue, "orange": .orange,
        "red": .red, "purple": .purple
    ]

    var filteredLogs: [OperationLog] {
        var result = logs
        if let type = selectedType {
            result = result.filter { $0.type == type }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.summary.localizedCaseInsensitiveContains(searchText)
                || $0.detail.localizedCaseInsensitiveContains(searchText)
                || ($0.roomNumber ?? "").contains(searchText)
            }
        }
        return result
    }

    /// 按日期分组
    private var groupedLogs: [(String, [OperationLog])] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日"
        let grouped = Dictionary(grouping: filteredLogs) { log in
            formatter.string(from: log.timestamp)
        }
        return grouped.sorted { a, b in
            (a.value.first?.timestamp ?? .distantPast) > (b.value.first?.timestamp ?? .distantPast)
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 类型筛选
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        filterChip(label: "全部", isSelected: selectedType == nil) {
                            selectedType = nil
                        }
                        ForEach(typeFilters) { type in
                            filterChip(label: type.rawValue, isSelected: selectedType == type) {
                                selectedType = (selectedType == type) ? nil : type
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }
                .background(Color(.systemGroupedBackground))

                if filteredLogs.isEmpty {
                    ContentUnavailableView(
                        "暂无日志",
                        systemImage: "doc.text",
                        description: Text(selectedType != nil ? "没有「\(selectedType!.rawValue)」类型的记录" : "还没有操作记录")
                    )
                } else {
                    List {
                        ForEach(groupedLogs, id: \.0) { dateStr, dayLogs in
                            Section {
                                ForEach(dayLogs) { log in
                                    logRow(log)
                                }
                            } header: {
                                HStack {
                                    Text(dateStr)
                                    Spacer()
                                    Text("\(dayLogs.count) 条")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("操作日志")
            .searchable(text: $searchText, prompt: "搜索房号、客人、操作...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("导出当前筛选 CSV") {
                            exportLogs(format: .csv)
                        }
                        Button("导出当前筛选 JSON") {
                            exportLogs(format: .json)
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Text("\(filteredLogs.count)/\(logs.count) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .onAppear {
                logs = logService.fetchAll()
            }
            .refreshable {
                logs = logService.fetchAll()
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
    }

    // MARK: - 日志行

    private func logRow(_ log: OperationLog) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：图标 + 类型 + 时间
            HStack(spacing: 8) {
                Image(systemName: log.type.icon)
                    .foregroundStyle(colorMap[log.type.color] ?? .gray)
                    .font(.callout)

                Text(log.type.rawValue)
                    .font(.caption)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((colorMap[log.type.color] ?? .gray).opacity(0.12))
                    .clipShape(Capsule())

                if let room = log.roomNumber {
                    Text(room)
                        .font(.caption)
                        .fontWeight(.bold)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())
                }

                Spacer()

                Text(formatTime(log.timestamp))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // 第二行：摘要
            Text(log.summary)
                .font(.subheadline)
                .fontWeight(.medium)

            // 第三行：详情
            Text(log.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            // 第四行：操作者
            HStack {
                Image(systemName: log.operatorRole == "管理员" ? "person.badge.key" : "person")
                    .font(.caption2)
                Text("\(log.operatorName)（\(log.operatorRole)）")
                    .font(.caption2)
            }
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 筛选标签

    private func filterChip(label: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.caption)
                .fontWeight(isSelected ? .bold : .regular)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.blue : Color(.tertiarySystemFill))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }

    // MARK: - 时间格式化

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private func exportLogs(format: OperationLogService.ExportFormat) {
        do {
            exportURL = try logService.exportLogs(filteredLogs, format: format)
            showExportShare = true
        } catch {
            resultMessage = error.localizedDescription
            showResult = true
        }
    }
}
