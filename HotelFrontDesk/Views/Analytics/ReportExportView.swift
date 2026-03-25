import SwiftUI

/// 报表导出页面（管理员专用）
struct ReportExportView: View {
    @State private var selectedYear: Int
    @State private var selectedMonth: Int
    @State private var selectedDate = Date()
    @State private var isGenerating = false
    @State private var generatingType = ""
    @State private var shareURL: URL?
    @State private var showShare = false
    @State private var errorMessage: String?

    init() {
        let now = Date()
        let cal = Calendar.current
        _selectedYear = State(initialValue: cal.component(.year, from: now))
        _selectedMonth = State(initialValue: cal.component(.month, from: now))
    }

    var body: some View {
        List {
            // 月份选择
            Section("选择月份") {
                HStack {
                    Button {
                        goToPrevMonth()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    Spacer()
                    Text("\(selectedYear)年\(selectedMonth)月")
                        .font(.headline)
                    Spacer()
                    Button {
                        goToNextMonth()
                    } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(isCurrentMonth)
                }
            }

            // 月度报表
            Section("月度报表") {
                reportButton(
                    icon: "chart.bar.doc.horizontal",
                    title: "月度经营报表",
                    desc: "营收、入住率、ADR、房型分析",
                    color: .blue
                ) {
                    try await ReportGenerator.monthlyReport(year: selectedYear, month: selectedMonth)
                }

                reportButton(
                    icon: "yensign.circle",
                    title: "财务数据报表",
                    desc: "损益汇总、成本明细、利润分析",
                    color: .green
                ) {
                    try await ReportGenerator.financeReport(year: selectedYear, month: selectedMonth)
                }

                reportButton(
                    icon: "person.3",
                    title: "客源分析报表",
                    desc: "客源排行、回头客、客均消费",
                    color: .orange
                ) {
                    try await ReportGenerator.guestReport(year: selectedYear, month: selectedMonth)
                }
            }

            // 年度报告
            Section("年度报告") {
                reportButton(
                    icon: "chart.line.uptrend.xyaxis.circle",
                    title: "年度经营报告",
                    desc: "全年营收/利润/月度趋势/季度汇总/房型分析/TOP20客源",
                    color: .indigo
                ) {
                    try await ReportGenerator.annualReport(year: selectedYear)
                }
            }

            // 每日报表
            Section("每日报表") {
                DatePicker("选择日期", selection: $selectedDate, displayedComponents: .date)

                reportButton(
                    icon: "doc.text",
                    title: "每日营收报表",
                    desc: "当日入住/退房、营收、房型统计",
                    color: .purple
                ) {
                    try await ReportGenerator.dailyRevenueReport(date: selectedDate)
                }
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            }
        }
        .navigationTitle("报表导出")
        .overlay {
            if isGenerating {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("正在生成\(generatingType)...")
                            .font(.subheadline)
                            .foregroundStyle(.white)
                    }
                    .padding(30)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .sheet(isPresented: $showShare) {
            if let url = shareURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - 报表按钮

    private func reportButton(
        icon: String,
        title: String,
        desc: String,
        color: Color,
        generator: @escaping () async throws -> URL
    ) -> some View {
        Button {
            Task {
                await generateReport(title: title, generator: generator)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "square.and.arrow.up")
                    .foregroundStyle(.blue)
                    .font(.callout)
            }
        }
        .disabled(isGenerating)
    }

    private func generateReport(title: String, generator: () async throws -> URL) async {
        isGenerating = true
        generatingType = title
        errorMessage = nil
        do {
            let url = try await generator()
            shareURL = url
            showShare = true
        } catch {
            errorMessage = "生成失败: \(ErrorHelper.userMessage(error))"
        }
        isGenerating = false
    }

    // MARK: - 月份导航

    private var isCurrentMonth: Bool {
        let now = Date()
        let cal = Calendar.current
        return selectedYear == cal.component(.year, from: now)
            && selectedMonth == cal.component(.month, from: now)
    }

    private func goToPrevMonth() {
        if selectedMonth == 1 {
            selectedYear -= 1
            selectedMonth = 12
        } else {
            selectedMonth -= 1
        }
    }

    private func goToNextMonth() {
        guard !isCurrentMonth else { return }
        if selectedMonth == 12 {
            selectedYear += 1
            selectedMonth = 1
        } else {
            selectedMonth += 1
        }
    }
}

/// UIKit ShareSheet 包装
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
