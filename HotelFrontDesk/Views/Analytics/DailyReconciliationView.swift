import SwiftUI

/// 日结对账页面
struct DailyReconciliationView: View {
    @StateObject private var vm = DailyReconciliationViewModel()
    @State private var selectedTab = 0
    @State private var showShareSheet = false
    @State private var shareURL: URL?

    var body: some View {
        VStack(spacing: 0) {
            // 标签切换
            Picker("", selection: $selectedTab) {
                Text("今日对账").tag(0)
                Text("历史记录").tag(1)
            }
            .pickerStyle(.segmented)
            .padding()

            if selectedTab == 0 {
                todayReconciliationTab
            } else {
                historyTab
            }
        }
        .navigationTitle("日结对账")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let url = vm.generateReportFile() {
                        shareURL = url
                        showShareSheet = true
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(vm.transactions.isEmpty)
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
        .alert("对账完成", isPresented: $vm.showCompletion) {
            Button("确定", role: .cancel) {}
        } message: {
            if vm.hasWarning {
                Text("注意：现金差异超过 ¥10，请核实原因。\n差异: ¥\(String(format: "%.2f", vm.variance))")
            } else {
                Text("今日对账已保存。")
            }
        }
        .task {
            await vm.loadTodayData()
        }
    }

    // MARK: - 今日对账

    private var todayReconciliationTab: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.isLoading {
                    ProgressView("加载数据中...")
                        .padding(.top, 40)
                } else {
                    if let error = vm.errorMessage {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                            .padding()
                    }

                    // 收入汇总卡片
                    incomeSummarySection

                    // 按支付方式明细
                    paymentMethodBreakdown

                    // 交易明细
                    transactionListSection

                    // 现金对账
                    cashReconciliationSection

                    // 备注
                    notesSection

                    // 完成对账按钮
                    completeButton
                }
            }
            .padding()
        }
    }

    // MARK: - 收入汇总

    private var incomeSummarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("今日收入汇总", systemImage: "yensign.circle.fill")
                    .font(.headline)
                Spacer()
                Text(Date().chineseDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                summaryCard("收款笔数", "\(vm.depositCount)", .blue)
                summaryCard("退款笔数", "\(vm.refundCount)", .orange)
                summaryCard("交易总数", "\(vm.transactions.count)", .purple)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("总收入").font(.caption).foregroundStyle(.secondary)
                    Text("¥\(String(format: "%.2f", vm.totalIncome))")
                        .font(.title3).fontWeight(.bold).foregroundStyle(.blue)
                }
                Spacer()
                VStack(alignment: .center, spacing: 4) {
                    Text("总退款").font(.caption).foregroundStyle(.secondary)
                    Text("¥\(String(format: "%.2f", vm.totalRefunds))")
                        .font(.title3).fontWeight(.bold).foregroundStyle(.orange)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    Text("净收入").font(.caption).foregroundStyle(.secondary)
                    Text("¥\(String(format: "%.2f", vm.totalIncome - vm.totalRefunds))")
                        .font(.title3).fontWeight(.bold).foregroundStyle(.green)
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.subtle)
    }

    private func summaryCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).fontWeight(.bold).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - 支付方式明细

    private var paymentMethodBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("按支付方式", systemImage: "creditcard.fill")
                .font(.headline)

            if vm.incomeByMethod.isEmpty {
                Text("今日暂无收款记录")
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                let sorted = vm.incomeByMethod.sorted { $0.value > $1.value }
                ForEach(sorted, id: \.key) { method, amount in
                    HStack(spacing: 12) {
                        Image(systemName: method.icon)
                            .font(.title3)
                            .foregroundStyle(iconColor(for: method))
                            .frame(width: 28)

                        Text(method.rawValue)
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Spacer()

                        Text("¥\(String(format: "%.2f", amount))")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(.textPrimary)

                        // 占比
                        if vm.totalIncome > 0 {
                            Text(String(format: "%.0f%%", amount / vm.totalIncome * 100))
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.subtle)
    }

    private func iconColor(for method: PaymentMethod) -> Color {
        switch method {
        case .cash: .green
        case .wechat: .green
        case .alipay: .blue
        case .bankCard: .orange
        case .pos: .purple
        case .transfer: .indigo
        }
    }

    // MARK: - 交易明细

    private var transactionListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("交易明细", systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text("共\(vm.transactions.count)笔")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            if vm.transactions.isEmpty {
                Text("今日暂无交易")
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(vm.transactions) { t in
                    HStack(spacing: 10) {
                        // 时间
                        Text(t.time.timeString)
                            .font(.caption)
                            .foregroundStyle(.textSecondary)
                            .frame(width: 45, alignment: .leading)

                        // 房号
                        if let room = t.roomNumber {
                            Text(room)
                                .font(.caption)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.blue.opacity(0.1))
                                .clipShape(Capsule())
                        }

                        // 描述
                        Text(t.description)
                            .font(.subheadline)

                        Spacer()

                        // 支付方式
                        Text(t.paymentMethod.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.textSecondary)

                        // 金额
                        Text("\(t.type == .collect ? "+" : "-")¥\(String(format: "%.0f", t.amount))")
                            .font(.subheadline)
                            .fontWeight(.bold)
                            .foregroundStyle(t.type == .collect ? .green : .red)
                    }
                    .padding(.vertical, 4)

                    if t.id != vm.transactions.last?.id {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.subtle)
    }

    // MARK: - 现金对账

    private var cashReconciliationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("现金对账", systemImage: "banknote.fill")
                .font(.headline)

            // 开店现金
            HStack {
                Text("开店现金")
                    .font(.subheadline)
                Spacer()
                HStack(spacing: 4) {
                    Text("¥")
                        .foregroundStyle(.textSecondary)
                    TextField("0", text: $vm.openingBalance)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
            }

            Divider()

            // 预期现金
            HStack {
                Text("预期现金余额")
                    .font(.subheadline)
                Spacer()
                Text("¥\(String(format: "%.2f", vm.expectedCash))")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundStyle(.blue)
            }

            // 计算说明
            let cashIncome = vm.incomeByMethod[.cash] ?? 0
            let cashRefunds = vm.todayDeposits
                .filter { $0.type == .refund && $0.paymentMethod == .cash }
                .reduce(0) { $0 + $1.amount }

            Text("= 开店现金(¥\(vm.openingBalance)) + 现金收入(¥\(String(format: "%.0f", cashIncome))) - 现金退款(¥\(String(format: "%.0f", cashRefunds)))")
                .font(.caption)
                .foregroundStyle(.textSecondary)

            Divider()

            // 实际现金
            HStack {
                Text("实际清点现金")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                HStack(spacing: 4) {
                    Text("¥")
                        .foregroundStyle(.textSecondary)
                    TextField("输入实际金额", text: $vm.actualCashCount)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // 差异显示
            if !vm.actualCashCount.isEmpty {
                Divider()

                HStack {
                    Text("差异")
                        .font(.subheadline)
                        .fontWeight(.bold)
                    Spacer()

                    HStack(spacing: 6) {
                        if vm.hasWarning {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        } else {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }

                        Text("¥\(String(format: "%.2f", vm.variance))")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(varianceColor)
                    }
                }

                if vm.hasWarning {
                    Text("差异超过 ¥10，请在备注中说明原因")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 8)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.subtle)
    }

    private var varianceColor: Color {
        if abs(vm.variance) <= 10 {
            return .green
        }
        return .red
    }

    // MARK: - 备注

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("备注", systemImage: "note.text")
                .font(.headline)

            TextEditor(text: $vm.notes)
                .frame(minHeight: 60, maxHeight: 120)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )

            if vm.notes.isEmpty {
                Text("可记录特殊情况、差异原因等")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.subtle)
    }

    // MARK: - 完成按钮

    private var completeButton: some View {
        VStack(spacing: 8) {
            if vm.todayAlreadyReconciled {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("今日已完成对账")
                        .fontWeight(.medium)
                        .foregroundStyle(.green)
                }
                .padding()
            }

            Button {
                vm.completeReconciliation()
            } label: {
                HStack {
                    Spacer()
                    Image(systemName: "checkmark.circle.fill")
                    Text("完成对账")
                        .fontWeight(.bold)
                    Spacer()
                }
                .padding()
                .background(vm.actualCashCount.isEmpty ? Color.gray : Color.indigo)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(vm.actualCashCount.isEmpty)
        }
    }

    // MARK: - 历史记录

    private var historyTab: some View {
        ScrollView {
            VStack(spacing: 12) {
                if vm.history.isEmpty {
                    ContentUnavailableView(
                        "暂无历史记录",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("完成每日对账后，记录将显示在这里")
                    )
                } else {
                    ForEach(vm.history) { record in
                        historyCard(record)
                    }
                }
            }
            .padding()
        }
    }

    private func historyCard(_ record: ReconciliationRecord) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            // 标题行
            HStack {
                Text(record.date.chineseDate)
                    .font(.headline)
                    .fontWeight(.bold)
                Spacer()
                Text(record.operatorName)
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            Divider()

            // 数据行
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                historyItem("总收入", "¥\(String(format: "%.0f", record.totalIncome))", .blue)
                historyItem("交易笔数", "\(record.depositCount + record.refundCount)", .purple)
                historyItem("预期现金", "¥\(String(format: "%.0f", record.expectedCash))", .orange)
                historyItem("实际现金", "¥\(String(format: "%.0f", record.actualCash))", .green)
            }

            // 差异
            HStack {
                Text("现金差异")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
                Spacer()
                HStack(spacing: 4) {
                    if abs(record.variance) > 10 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text("¥\(String(format: "%.2f", record.variance))")
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundStyle(abs(record.variance) <= 10 ? .green : .red)
                }
            }

            // 支付方式明细
            if !record.incomeByMethod.isEmpty {
                Divider()
                HStack(spacing: 12) {
                    ForEach(record.incomeByMethod.sorted(by: { $0.value > $1.value }), id: \.key) { method, amount in
                        VStack(spacing: 2) {
                            Text("¥\(String(format: "%.0f", amount))")
                                .font(.caption)
                                .fontWeight(.bold)
                            Text(method)
                                .font(.caption2)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    Spacer()
                }
            }

            // 备注
            if !record.notes.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: "note.text")
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                    Text(record.notes)
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.subtle)
    }

    private func historyItem(_ label: String, _ value: String, _ color: Color) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(color)
        }
    }
}

#Preview {
    NavigationStack {
        DailyReconciliationView()
    }
}
