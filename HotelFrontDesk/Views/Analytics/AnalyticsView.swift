import SwiftUI
import Charts

struct AnalyticsView: View {
    @StateObject private var vm = AnalyticsViewModel()
    @ObservedObject private var appSettings = AppSettings.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // 月份选择器
                    monthSelector

                    if vm.isLoading {
                        ProgressView("加载数据中...")
                            .padding(.top, 40)
                    } else if vm.monthlyReservations.isEmpty && vm.dailyOccupancyData.isEmpty {
                        ContentUnavailableView(
                            "暂无数据",
                            systemImage: "chart.bar.xaxis",
                            description: Text("\(vm.monthTitle) 没有入住记录")
                        )
                    } else {
                        // KPI 卡片
                        kpiCards

                        // 盈亏分析（仅管理员）
                        if appSettings.isManagerMode {
                            profitSection
                        }

                        // 每日收入柱状图
                        dailyRevenueChart

                        // 入住率折线图
                        occupancyChart

                        // 房型收入饼图
                        roomTypePieChart

                        // 月度对比
                        monthCompare

                        // 房间排行
                        roomRanking

                        // 客源排行
                        guestRanking
                    }
                }
                .padding()
            }
            .navigationTitle("数据分析")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            DailyReconciliationView()
                        } label: {
                            Image(systemName: "checkmark.seal.fill")
                        }
                        NavigationLink {
                            NightAuditView()
                        } label: {
                            Image(systemName: "moon.stars.fill")
                        }
                        NavigationLink {
                            ReportExportView()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
            .refreshable {
                await vm.loadData()
            }
            .task {
                await vm.loadData()
            }
        }
    }

    // MARK: - 月份选择器
    private var monthSelector: some View {
        HStack {
            Button {
                vm.goToPreviousMonth()
            } label: {
                Image(systemName: "chevron.left.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
            }

            Spacer()

            Text(vm.monthTitle)
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            Button {
                vm.goToNextMonth()
            } label: {
                Image(systemName: "chevron.right.circle.fill")
                    .font(.title2)
                    .foregroundStyle(vm.isCurrentMonth ? .gray : .blue)
            }
            .disabled(vm.isCurrentMonth)
        }
        .padding(.horizontal)
    }

    // MARK: - KPI 卡片
    private var kpiCards: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            kpiCard(
                icon: "yensign.circle.fill",
                iconColor: .blue,
                title: "月收入",
                value: "¥\(formatNumber(vm.monthlyRevenue))",
                change: vm.revenueChange,
                suffix: "%"
            )

            kpiCard(
                icon: "bed.double.circle.fill",
                iconColor: .green,
                title: "入住率",
                value: String(format: "%.1f%%", vm.occupancyRate),
                change: vm.occupancyChange,
                suffix: "pp"
            )

            kpiCard(
                icon: "banknote.fill",
                iconColor: .orange,
                title: "平均房价(ADR)",
                value: "¥\(Int(vm.averageDailyRate))",
                change: vm.adrChange,
                suffix: "%"
            )

            kpiCard(
                icon: "moon.stars.fill",
                iconColor: .purple,
                title: "总间夜",
                value: "\(vm.totalNights) 晚",
                change: vm.prevTotalNights > 0 ? Double(vm.totalNights - vm.prevTotalNights) / Double(vm.prevTotalNights) * 100 : nil,
                suffix: "%"
            )
        }
    }

    private func kpiCard(icon: String, iconColor: Color, title: String, value: String, change: Double?, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(iconColor)
                Spacer()
                if let change = change {
                    HStack(spacing: 2) {
                        Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text(String(format: "%.1f%@", abs(change), suffix))
                    }
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(change >= 0 ? .green : .red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((change >= 0 ? Color.green : Color.red).opacity(0.1))
                    .clipShape(Capsule())
                }
            }

            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundStyle(.textPrimary)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(.textSecondary)
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .luxuryShadow(.subtle)
    }

    // MARK: - 每日收入柱状图
    private var dailyRevenueChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("每日收入", systemImage: "chart.bar.fill")
                    .font(.headline)
                Spacer()
                Text("总计 ¥\(formatNumber(vm.monthlyRevenue))")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            Chart(vm.dailyRevenueData) { item in
                BarMark(
                    x: .value("日期", item.day),
                    y: .value("收入", item.revenue)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.blue, .blue.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { value in
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text("\(day)日")
                                .font(.caption)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("¥\(formatNumber(v))")
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 入住率折线图
    private var occupancyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("每日入住率", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.headline)
                Spacer()
                Text("平均 \(String(format: "%.1f%%", vm.occupancyRate))")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            Chart(vm.dailyOccupancyRates) { item in
                LineMark(
                    x: .value("日期", item.day),
                    y: .value("入住率", item.rate)
                )
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("日期", item.day),
                    y: .value("入住率", item.rate)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.green.opacity(0.3), .green.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .stride(by: 5)) { value in
                    AxisValueLabel {
                        if let day = value.as(Int.self) {
                            Text("\(day)日")
                                .font(.caption)
                        }
                    }
                    AxisGridLine()
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))%")
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(height: 200)
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 房型饼图
    private var roomTypePieChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("房型收入占比", systemImage: "chart.pie.fill")
                .font(.headline)

            if vm.roomTypeBreakdown.isEmpty {
                Text("暂无数据")
                    .foregroundStyle(.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                HStack(spacing: 20) {
                    // 饼图
                    Chart(vm.roomTypeBreakdown) { item in
                        SectorMark(
                            angle: .value("收入", item.revenue),
                            innerRadius: .ratio(0.55),
                            angularInset: 2
                        )
                        .foregroundStyle(item.color)
                        .cornerRadius(4)
                    }
                    .frame(width: 150, height: 150)

                    // 图例
                    VStack(alignment: .leading, spacing: 10) {
                        let totalRevenue = vm.roomTypeBreakdown.reduce(0) { $0 + $1.revenue }
                        ForEach(vm.roomTypeBreakdown) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.color)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.type)
                                        .font(.subheadline)
                                        .fontWeight(.medium)
                                    Text("¥\(formatNumber(item.revenue)) · \(item.count)次 · \(totalRevenue > 0 ? Int(item.revenue / totalRevenue * 100) : 0)%")
                                        .font(.caption)
                                        .foregroundStyle(.textSecondary)
                                }
                            }
                        }
                    }

                    Spacer()
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 月度对比
    private var monthCompare: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("月度对比", systemImage: "arrow.left.arrow.right")
                .font(.headline)

            let (prevY, prevM) = vm.selectedMonth == 1 ? (vm.selectedYear - 1, 12) : (vm.selectedYear, vm.selectedMonth - 1)
            let prevTitle = "\(prevY)年\(prevM)月"

            HStack(spacing: 0) {
                // 上月
                VStack(spacing: 8) {
                    Text(prevTitle)
                        .font(.caption)
                        .foregroundStyle(.textSecondary)
                    compareItem(label: "收入", value: "¥\(formatNumber(vm.prevMonthRevenue))")
                    compareItem(label: "间夜", value: "\(vm.prevTotalNights)")
                    compareItem(label: "ADR", value: "¥\(Int(vm.prevADR))")
                }
                .frame(maxWidth: .infinity)

                // 箭头
                VStack(spacing: 8) {
                    Text("")
                        .font(.caption)
                    compareArrow(vm.revenueChange)
                    compareArrow(vm.prevTotalNights > 0 ? Double(vm.totalNights - vm.prevTotalNights) / Double(vm.prevTotalNights) * 100 : nil)
                    compareArrow(vm.adrChange)
                }
                .frame(width: 60)

                // 当月
                VStack(spacing: 8) {
                    Text(vm.monthTitle)
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.blue)
                    compareItem(label: "收入", value: "¥\(formatNumber(vm.monthlyRevenue))")
                    compareItem(label: "间夜", value: "\(vm.totalNights)")
                    compareItem(label: "ADR", value: "¥\(Int(vm.averageDailyRate))")
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func compareItem(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, 4)
    }

    private func compareArrow(_ change: Double?) -> some View {
        Group {
            if let change = change {
                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    .font(.caption)
                    .foregroundStyle(change >= 0 ? .green : .red)
            } else {
                Image(systemName: "minus")
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - 房间排行
    private var roomRanking: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("房间收入排行 TOP 10", systemImage: "trophy.fill")
                .font(.headline)

            if vm.topRooms.isEmpty {
                Text("暂无数据").foregroundStyle(.textSecondary)
            } else {
                ForEach(Array(vm.topRooms.enumerated()), id: \.element.id) { index, room in
                    HStack(spacing: 12) {
                        // 排名
                        Text("\(index + 1)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(index < 3 ? .orange : .secondary)
                            .frame(width: 24)

                        // 房号
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.roomNumber)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text("\(room.roomType) · \(room.count)次入住")
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                        }

                        Spacer()

                        // 收入
                        VStack(alignment: .trailing, spacing: 2) {
                            Text("¥\(formatNumber(room.revenue))")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                            Text("均价¥\(Int(room.avgRate))/晚")
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if index < vm.topRooms.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 客源排行
    private var guestRanking: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("客源排行 TOP 10", systemImage: "person.3.fill")
                .font(.headline)

            if vm.topGuests.isEmpty {
                Text("暂无数据").foregroundStyle(.textSecondary)
            } else {
                ForEach(Array(vm.topGuests.enumerated()), id: \.element.id) { index, guest in
                    HStack(spacing: 12) {
                        Text("\(index + 1)")
                            .font(.headline)
                            .fontWeight(.bold)
                            .foregroundStyle(index < 3 ? .orange : .secondary)
                            .frame(width: 24)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(guest.name)
                                .font(.subheadline)
                                .fontWeight(.bold)
                            Text(guest.phone)
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                        }

                        Spacer()

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("¥\(formatNumber(guest.totalSpent))")
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .foregroundStyle(.green)
                            Text("\(guest.count)次入住")
                                .font(.caption)
                                .foregroundStyle(.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)

                    if index < vm.topGuests.count - 1 {
                        Divider()
                    }
                }
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 盈亏分析
    private var profitSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("盈亏分析", systemImage: "chart.line.uptrend.xyaxis")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                profitItem(
                    label: "月收入",
                    value: "¥\(formatNumber(vm.monthlyRevenue))",
                    color: .blue
                )
                profitItem(
                    label: "月成本",
                    value: "¥\(formatNumber(vm.monthlyCost))",
                    color: .orange
                )
                profitItem(
                    label: "月利润",
                    value: "¥\(formatNumber(vm.monthlyProfit))",
                    color: vm.monthlyProfit >= 0 ? .green : .red
                )
            }

            // 利润率条
            HStack(spacing: 8) {
                Text("利润率")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)

                GeometryReader { geo in
                    let margin = max(min(vm.profitMargin / 100, 1), -1)
                    let barWidth = abs(margin) * geo.size.width
                    ZStack(alignment: margin >= 0 ? .leading : .trailing) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color(.systemGray5))
                        RoundedRectangle(cornerRadius: 4)
                            .fill(margin >= 0 ? .green : .red)
                            .frame(width: barWidth)
                    }
                }
                .frame(height: 8)

                Text(String(format: "%.1f%%", vm.profitMargin))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(vm.monthlyProfit >= 0 ? .green : .red)
                    .frame(width: 55, alignment: .trailing)
            }
            .padding(.top, 4)

            if let change = vm.profitChange {
                HStack(spacing: 4) {
                    Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                    Text("环比\(change >= 0 ? "增长" : "下降") \(String(format: "%.1f%%", abs(change)))")
                }
                .font(.caption)
                .foregroundStyle(change >= 0 ? .green : .red)
            }
        }
        .padding()
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func profitItem(label: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(color)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.textSecondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - 辅助
    private func formatNumber(_ value: Double) -> String {
        if value >= 10000 {
            return String(format: "%.1f万", value / 10000)
        }
        return "\(Int(value))"
    }
}

#Preview {
    AnalyticsView()
}
