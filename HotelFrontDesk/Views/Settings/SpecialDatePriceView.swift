import SwiftUI

/// 特殊日期定价管理 — 日历视图
struct SpecialDatePriceView: View {
    @ObservedObject private var pricingService = PricingService.shared
    @State private var specialDates: [SpecialDatePrice] = []
    @State private var displayedMonth = Date()
    @State private var showAddSheet = false
    @State private var editingItem: SpecialDatePrice?

    // 添加/编辑表单
    @State private var formName = ""
    @State private var formStart = Date()
    @State private var formEnd = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    @State private var formKingPrice = ""
    @State private var formTwinPrice = ""
    @State private var formSuitePrice = ""

    private let logService = OperationLogService.shared
    private let calendar = Calendar.current
    private let weekdaySymbols = ["日", "一", "二", "三", "四", "五", "六"]

    // 日期 → 特殊事件缓存
    @State private var dateEventMap: [String: SpecialDatePrice] = [:]

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 说明
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.appAccent)
                    Text("周末自动标出 · 点击日期可添加特殊事件")
                        .font(.subheadline)
                        .foregroundStyle(.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // 日历卡片
                calendarCard
                    .padding(.horizontal, 16)

                // 特殊事件列表
                if !specialDates.isEmpty {
                    eventListSection
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 20)
        }
        .background(Color.appBackground)
        .navigationTitle("特殊日期定价")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    resetForm()
                    editingItem = nil
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { refresh() }
        .sheet(isPresented: $showAddSheet, onDismiss: refresh) {
            formSheet
        }
    }

    // MARK: - 日历卡片
    private var calendarCard: some View {
        VStack(spacing: 14) {
            // 月份导航
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { changeMonth(-1) }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.textPrimary)
                }

                Spacer()

                Text(monthTitle)
                    .font(.headline)
                    .foregroundStyle(.textPrimary)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { changeMonth(1) }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .fontWeight(.medium)
                        .foregroundStyle(.textPrimary)
                }
            }
            .padding(.horizontal, 4)

            // 星期标题行
            HStack(spacing: 0) {
                ForEach(weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 日期网格
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }

            // 图例
            HStack(spacing: 20) {
                legendItem(color: .appAccent.opacity(0.2), text: "周末", borderColor: .appAccent.opacity(0.4))
                legendItem(color: .orange.opacity(0.2), text: "特殊事件", borderColor: .orange.opacity(0.5))
                HStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(Color.blue, lineWidth: 1.5)
                        .frame(width: 12, height: 12)
                    Text("今天")
                }
            }
            .font(.caption)
            .foregroundStyle(.textSecondary)
        }
        .padding(16)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .luxuryShadow(.subtle)
    }

    // MARK: - 日期单元格
    @ViewBuilder
    private func dayCell(_ day: DateComponents) -> some View {
        if let dayNum = day.day, let date = calendar.date(from: day) {
            let isToday = calendar.isDateInToday(date)
            let weekday = calendar.component(.weekday, from: date)
            let isWeekend = PricingService.weekendDays.contains(weekday)
            let event = eventForDate(date)
            let hasEvent = event != nil

            Button {
                if let event = event {
                    startEditing(event)
                } else {
                    resetForm()
                    formStart = date
                    formEnd = date
                    editingItem = nil
                    showAddSheet = true
                }
            } label: {
                VStack(spacing: 2) {
                    // 日期数字 + 周末标记
                    ZStack(alignment: .topTrailing) {
                        Text("\(dayNum)")
                            .font(.system(size: 15, weight: isToday ? .bold : .regular))
                            .foregroundStyle(
                                hasEvent ? .white :
                                isToday ? .blue :
                                .textPrimary
                            )
                            .frame(maxWidth: .infinity)

                        if isWeekend && !hasEvent {
                            Text("末")
                                .font(.system(size: 7, weight: .bold))
                                .foregroundStyle(.appAccent)
                                .offset(x: -2, y: 2)
                        }
                    }

                    // 事件名缩写
                    if let event = event {
                        Text(String(event.name.prefix(3)))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    } else {
                        Text(" ")
                            .font(.system(size: 8))
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(
                    Group {
                        if hasEvent {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.85))
                        } else if isWeekend {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.appAccent.opacity(0.12))
                        } else if isToday {
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.blue, lineWidth: 1.5)
                        }
                    }
                )
            }
            .buttonStyle(.plain)
        } else {
            // 空白占位
            Text("")
                .frame(maxWidth: .infinity)
                .frame(height: 44)
        }
    }

    // MARK: - 特殊事件列表
    private var eventListSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已设特殊事件")
                    .font(.headline)
                    .foregroundStyle(.textPrimary)
                Spacer()
                Text("\(specialDates.count) 条")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)
            }

            ForEach(specialDates) { item in
                eventRow(item)
            }
        }
    }

    private func eventRow(_ item: SpecialDatePrice) -> some View {
        HStack(spacing: 12) {
            // 左侧色条
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.orange)
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(item.name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(.textPrimary)
                    if !item.isActive {
                        Text("已停用")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.appError.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                Text("\(formatDate(item.startDate)) ~ \(formatDate(item.endDate))")
                    .font(.caption)
                    .foregroundStyle(.textSecondary)

                // 价格标签
                HStack(spacing: 8) {
                    ForEach(RoomType.allCases) { type in
                        if let price = item.price(for: type) {
                            HStack(spacing: 3) {
                                Text(type.rawValue)
                                    .font(.caption2)
                                Text("¥\(Int(price))")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                }
            }

            Spacer()

            // 编辑按钮
            Button {
                startEditing(item)
            } label: {
                Image(systemName: "pencil.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.textSecondary.opacity(0.5))
            }
        }
        .padding(12)
        .background(Color.appCard)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .luxuryShadow(.subtle)
        .opacity(item.isActive ? 1 : 0.5)
    }

    // MARK: - 添加/编辑表单 Sheet
    private var formSheet: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    HStack {
                        Text("名称")
                        Spacer()
                        TextField("如 马拉松、国庆节", text: $formName)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("开始日期", selection: $formStart, displayedComponents: .date)
                    DatePicker("结束日期", selection: $formEnd, in: formStart..., displayedComponents: .date)
                }

                Section("各房型特价") {
                    HStack {
                        Text("大床房 ¥")
                        TextField("留空=不调整", text: $formKingPrice)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("双床房 ¥")
                        TextField("留空=不调整", text: $formTwinPrice)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("套房 ¥")
                        TextField("留空=不调整", text: $formSuitePrice)
                            .keyboardType(.numberPad)
                    }
                }

                Section {
                    Label("留空的房型将使用该日期对应的平日价或周末价", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let editing = editingItem {
                    Section {
                        Button(role: .destructive) {
                            pricingService.deleteSpecialDate(id: editing.id)
                            logService.log(
                                type: .roomEdit,
                                summary: "删除特殊定价「\(editing.name)」",
                                detail: "名称: \(editing.name) | \(formatDate(editing.startDate)) ~ \(formatDate(editing.endDate))"
                            )
                            showAddSheet = false
                        } label: {
                            HStack {
                                Spacer()
                                Label("删除此事件", systemImage: "trash")
                                Spacer()
                            }
                        }
                    }
                }
            }
            .navigationTitle(editingItem != nil ? "编辑事件" : "添加特殊事件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showAddSheet = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editingItem != nil ? "保存" : "添加") {
                        save()
                    }
                    .fontWeight(.bold)
                    .disabled(formName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 保存逻辑
    private func save() {
        var prices: [String: Double] = [:]
        if let p = Double(formKingPrice), p > 0 { prices[RoomType.king.rawValue] = p }
        if let p = Double(formTwinPrice), p > 0 { prices[RoomType.twin.rawValue] = p }
        if let p = Double(formSuitePrice), p > 0 { prices[RoomType.suite.rawValue] = p }

        if let editing = editingItem {
            var updated = editing
            updated.name = formName.trimmingCharacters(in: .whitespaces)
            updated.startDate = formStart
            updated.endDate = formEnd
            updated.priceByRoomType = prices
            pricingService.updateSpecialDate(updated)
            logService.log(
                type: .roomEdit,
                summary: "编辑特殊定价「\(updated.name)」",
                detail: "名称: \(updated.name) | \(formatDate(updated.startDate)) ~ \(formatDate(updated.endDate)) | \(pricesSummary(prices))"
            )
        } else {
            let item = SpecialDatePrice(
                name: formName.trimmingCharacters(in: .whitespaces),
                startDate: formStart,
                endDate: formEnd,
                priceByRoomType: prices
            )
            pricingService.addSpecialDate(item)
            logService.log(
                type: .roomAdd,
                summary: "新增特殊定价「\(item.name)」",
                detail: "名称: \(item.name) | \(formatDate(item.startDate)) ~ \(formatDate(item.endDate)) | \(pricesSummary(prices))"
            )
        }
        showAddSheet = false
    }

    private func startEditing(_ item: SpecialDatePrice) {
        editingItem = item
        formName = item.name
        formStart = item.startDate
        formEnd = item.endDate
        formKingPrice = item.price(for: .king).map { String(Int($0)) } ?? ""
        formTwinPrice = item.price(for: .twin).map { String(Int($0)) } ?? ""
        formSuitePrice = item.price(for: .suite).map { String(Int($0)) } ?? ""
        showAddSheet = true
    }

    private func resetForm() {
        formName = ""
        formStart = Date()
        formEnd = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        formKingPrice = ""
        formTwinPrice = ""
        formSuitePrice = ""
    }

    private func refresh() {
        specialDates = pricingService.fetchAll()
        rebuildEventMap()
    }

    // MARK: - 事件映射

    private func rebuildEventMap() {
        var map: [String: SpecialDatePrice] = [:]
        for item in specialDates where item.isActive {
            var current = calendar.startOfDay(for: item.startDate)
            let end = calendar.startOfDay(for: item.endDate)
            while current <= end {
                map[dateKey(current)] = item
                guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
                current = next
            }
        }
        dateEventMap = map
    }

    private func eventForDate(_ date: Date) -> SpecialDatePrice? {
        dateEventMap[dateKey(date)]
    }

    // MARK: - 日历计算

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy年M月"
        return formatter.string(from: displayedMonth)
    }

    private func changeMonth(_ delta: Int) {
        if let newMonth = calendar.date(byAdding: .month, value: delta, to: displayedMonth) {
            displayedMonth = newMonth
        }
    }

    private func daysInMonth() -> [DateComponents] {
        let year = calendar.component(.year, from: displayedMonth)
        let month = calendar.component(.month, from: displayedMonth)

        let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1))!
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)
        let numDays = calendar.range(of: .day, in: .month, for: firstOfMonth)!.count

        var days: [DateComponents] = []

        // 前面的空白
        for _ in 0..<(firstWeekday - 1) {
            days.append(DateComponents())
        }

        // 每天
        for day in 1...numDays {
            days.append(DateComponents(year: year, month: month, day: day))
        }

        return days
    }

    private func dateKey(_ date: Date) -> String {
        let y = calendar.component(.year, from: date)
        let m = calendar.component(.month, from: date)
        let d = calendar.component(.day, from: date)
        return "\(y)-\(m)-\(d)"
    }

    // MARK: - 格式化

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d"
        return f.string(from: date)
    }

    private func pricesSummary(_ prices: [String: Double]) -> String {
        prices.map { "\($0.key) ¥\(Int($0.value))" }.joined(separator: " | ")
    }

    // MARK: - 图例组件

    private func legendItem(color: Color, text: String, borderColor: Color) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(borderColor, lineWidth: 0.5)
                )
                .frame(width: 12, height: 12)
            Text(text)
        }
    }
}
