import UIKit
import PDFKit

/// 报表生成器 — 生成 PDF 格式的经营报表
@MainActor
enum ReportGenerator {

    // MARK: - 每日营收报表

    static func dailyRevenueReport(date: Date) async throws -> URL {
        let service = CloudKitService.shared
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: date)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            throw NSError(domain: "ReportGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid date calculation"])
        }

        let allReservations = try await service.fetchAllReservations()
        let rooms = try await service.fetchAllRooms()

        // 当天退房的记录
        let dayCheckOuts = allReservations.filter { res in
            guard let checkOut = res.actualCheckOut else { return false }
            return checkOut >= startOfDay && checkOut < endOfDay
        }
        // 当天入住的记录
        let dayCheckIns = allReservations.filter { res in
            res.checkInDate >= startOfDay && res.checkInDate < endOfDay
        }
        // 当天在住
        let occupiedCount = allReservations.filter { res in
            res.isActive || (res.checkInDate <= date && (res.actualCheckOut ?? res.expectedCheckOut) >= startOfDay)
        }.count

        let totalRevenue = dayCheckOuts.reduce(0) { $0 + $1.totalRevenue }

        let dateStr = formatDate(date, format: "yyyy年M月d日")
        let fileName = "每日营收报表_\(formatDate(date, format: "yyyyMMdd"))"

        var lines: [(String, String)] = [
            ("报表日期", dateStr),
            ("", ""),
            ("当日入住", "\(dayCheckIns.count) 间"),
            ("当日退房", "\(dayCheckOuts.count) 间"),
            ("当前在住", "\(min(occupiedCount, rooms.count)) / \(rooms.count) 间"),
            ("入住率", rooms.count > 0 ? String(format: "%.1f%%", Double(min(occupiedCount, rooms.count)) / Double(rooms.count) * 100) : "0%"),
            ("", ""),
            ("当日营收", "¥\(formatMoney(totalRevenue))"),
        ]

        // 按房型统计
        let roomMap = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        var typeRevenue: [String: (count: Int, revenue: Double)] = [:]
        for res in dayCheckOuts {
            let typeName = roomMap[res.roomID]?.roomType.rawValue ?? "未知"
            let existing = typeRevenue[typeName] ?? (count: 0, revenue: 0)
            typeRevenue[typeName] = (count: existing.count + 1, revenue: existing.revenue + res.totalRevenue)
        }
        lines.append(("", ""))
        lines.append(("【按房型】", ""))
        for (type, data) in typeRevenue.sorted(by: { $0.value.revenue > $1.value.revenue }) {
            lines.append(("  \(type)", "\(data.count)间 ¥\(formatMoney(data.revenue))"))
        }

        // 退房明细
        lines.append(("", ""))
        lines.append(("【退房明细】", ""))
        for res in dayCheckOuts.sorted(by: { ($0.room?.roomNumber ?? "") < ($1.room?.roomNumber ?? "") }) {
            let roomNum = roomMap[res.roomID]?.roomNumber ?? "?"
            lines.append(("  \(roomNum)房", "\(res.nightsStayed)晚 ¥\(formatMoney(res.totalRevenue))"))
        }

        return generatePDF(title: "每日营收报表", subtitle: dateStr, lines: lines, fileName: fileName)
    }

    // MARK: - 月度经营报表

    static func monthlyReport(year: Int, month: Int) async throws -> URL {
        let service = CloudKitService.shared
        let rooms = try await service.fetchAllRooms()
        let reservations = try await service.fetchReservationsForMonth(year: year, month: month)
        let totalRooms = rooms.count
        let cal = Calendar.current
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = cal.range(of: .day, in: .month, for: firstOfMonth) else {
            throw NSError(domain: "ReportGenerator", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid date for \(year)-\(month)"])
        }
        let daysInMonth = dayRange.count

        let totalRevenue = reservations.reduce(0) { $0 + $1.totalRevenue }
        let totalNights = reservations.reduce(0) { $0 + $1.nightsStayed }
        let adr = totalNights > 0 ? totalRevenue / Double(totalNights) : 0
        let totalRoomNights = Double(totalRooms * daysInMonth)
        let occupancyData = try await service.fetchDailyOccupancy(year: year, month: month, totalRooms: totalRooms)
        let occupiedNights = occupancyData.reduce(0) { $0 + $1.count }
        let occupancyRate = totalRoomNights > 0 ? Double(occupiedNights) / totalRoomNights * 100 : 0
        let totalCost = rooms.reduce(0) { $0 + $1.monthlyCost }
        let profit = totalRevenue - totalCost

        let monthStr = "\(year)年\(month)月"
        let fileName = "月度经营报表_\(year)\(String(format: "%02d", month))"

        var lines: [(String, String)] = [
            ("报表月份", monthStr),
            ("总房间数", "\(totalRooms) 间"),
            ("", ""),
            ("【核心指标】", ""),
            ("月营收", "¥\(formatMoney(totalRevenue))"),
            ("月成本", "¥\(formatMoney(totalCost))"),
            ("月利润", "¥\(formatMoney(profit))"),
            ("利润率", profit != 0 && totalRevenue > 0 ? String(format: "%.1f%%", profit / totalRevenue * 100) : "0%"),
            ("", ""),
            ("总间夜数", "\(totalNights) 晚"),
            ("平均房价(ADR)", "¥\(formatMoney(adr))"),
            ("入住率", String(format: "%.1f%%", occupancyRate)),
            ("RevPAR", totalRooms > 0 ? "¥\(formatMoney(totalRevenue / Double(totalRooms)))" : "0"),
            ("", ""),
            ("退房笔数", "\(reservations.count) 笔"),
        ]

        // 按房型
        let roomMap = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        var typeStats: [String: (count: Int, revenue: Double, nights: Int)] = [:]
        for res in reservations {
            let typeName = roomMap[res.roomID]?.roomType.rawValue ?? "未知"
            let existing = typeStats[typeName] ?? (count: 0, revenue: 0, nights: 0)
            typeStats[typeName] = (count: existing.count + 1, revenue: existing.revenue + res.totalRevenue, nights: existing.nights + res.nightsStayed)
        }
        lines.append(("", ""))
        lines.append(("【房型分析】", ""))
        for (type, data) in typeStats.sorted(by: { $0.value.revenue > $1.value.revenue }) {
            let typeADR = data.nights > 0 ? data.revenue / Double(data.nights) : 0
            lines.append(("  \(type)", "\(data.count)笔 \(data.nights)晚 ¥\(formatMoney(data.revenue)) 均价¥\(Int(typeADR))"))
        }

        return generatePDF(title: "月度经营报表", subtitle: monthStr, lines: lines, fileName: fileName)
    }

    // MARK: - 客源分析报表

    static func guestReport(year: Int, month: Int) async throws -> URL {
        let service = CloudKitService.shared
        let reservations = try await service.fetchReservationsForMonth(year: year, month: month)

        var guestData: [String: (name: String, phone: String, count: Int, total: Double, nights: Int)] = [:]
        for res in reservations {
            let name = res.guest?.name ?? "未知"
            let phone = Validators.maskedPhone(res.guest?.phone ?? "")
            let existing = guestData[res.guestID] ?? (name: name, phone: phone, count: 0, total: 0, nights: 0)
            guestData[res.guestID] = (
                name: name, phone: phone,
                count: existing.count + 1,
                total: existing.total + res.totalRevenue,
                nights: existing.nights + res.nightsStayed
            )
        }
        let sorted = guestData.values.sorted { $0.total > $1.total }

        let monthStr = "\(year)年\(month)月"
        let fileName = "客源分析报表_\(year)\(String(format: "%02d", month))"

        var lines: [(String, String)] = [
            ("报表月份", monthStr),
            ("客人总数", "\(guestData.count) 人"),
            ("入住总笔数", "\(reservations.count) 笔"),
            ("", ""),
            ("【客源排行（按消费）】", ""),
        ]

        for (i, guest) in sorted.prefix(30).enumerated() {
            lines.append(("  \(i + 1). \(guest.name)", "\(guest.count)次 \(guest.nights)晚 ¥\(formatMoney(guest.total))"))
        }

        // 统计
        let repeatGuests = sorted.filter { $0.count > 1 }
        lines.append(("", ""))
        lines.append(("【统计】", ""))
        lines.append(("回头客数量", "\(repeatGuests.count) 人"))
        lines.append(("回头客占比", guestData.count > 0 ? String(format: "%.1f%%", Double(repeatGuests.count) / Double(guestData.count) * 100) : "0%"))
        lines.append(("客均消费", guestData.count > 0 ? "¥\(formatMoney(sorted.reduce(0) { $0 + $1.total } / Double(guestData.count)))" : "0"))

        return generatePDF(title: "客源分析报表", subtitle: monthStr, lines: lines, fileName: fileName)
    }

    // MARK: - 财务数据报表

    static func financeReport(year: Int, month: Int) async throws -> URL {
        let service = CloudKitService.shared
        let rooms = try await service.fetchAllRooms()
        let reservations = try await service.fetchReservationsForMonth(year: year, month: month)

        let totalRevenue = reservations.reduce(0) { $0 + $1.totalRevenue }
        let totalCost = rooms.reduce(0) { $0 + $1.monthlyCost }
        let profit = totalRevenue - totalCost

        // 按房型成本
        var typeCosts: [String: (count: Int, cost: Double, revenue: Double)] = [:]
        for room in rooms {
            let typeName = room.roomType.rawValue
            let existing = typeCosts[typeName] ?? (count: 0, cost: 0, revenue: 0)
            typeCosts[typeName] = (count: existing.count + 1, cost: existing.cost + room.monthlyCost, revenue: existing.revenue)
        }
        let roomMap = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })
        for res in reservations {
            let typeName = roomMap[res.roomID]?.roomType.rawValue ?? "未知"
            if var existing = typeCosts[typeName] {
                existing.revenue += res.totalRevenue
                typeCosts[typeName] = existing
            }
        }

        let monthStr = "\(year)年\(month)月"
        let fileName = "财务数据_\(year)\(String(format: "%02d", month))"

        var lines: [(String, String)] = [
            ("报表月份", monthStr),
            ("", ""),
            ("【损益汇总】", ""),
            ("营业收入", "¥\(formatMoney(totalRevenue))"),
            ("运营成本", "¥\(formatMoney(totalCost))"),
            ("营业利润", "¥\(formatMoney(profit))"),
            ("利润率", totalRevenue > 0 ? String(format: "%.1f%%", profit / totalRevenue * 100) : "N/A"),
            ("", ""),
            ("【成本明细（按房型）】", ""),
        ]

        for (type, data) in typeCosts.sorted(by: { $0.key < $1.key }) {
            let typeProfit = data.revenue - data.cost
            lines.append(("  \(type)（\(data.count)间）", ""))
            lines.append(("    收入", "¥\(formatMoney(data.revenue))"))
            lines.append(("    成本", "¥\(formatMoney(data.cost))"))
            lines.append(("    利润", "¥\(formatMoney(typeProfit))"))
        }

        lines.append(("", ""))
        lines.append(("【每间房月均】", ""))
        lines.append(("月均收入", rooms.count > 0 ? "¥\(formatMoney(totalRevenue / Double(rooms.count)))" : "0"))
        lines.append(("月均成本", rooms.count > 0 ? "¥\(formatMoney(totalCost / Double(rooms.count)))" : "0"))
        lines.append(("月均利润", rooms.count > 0 ? "¥\(formatMoney(profit / Double(rooms.count)))" : "0"))

        return generatePDF(title: "财务数据报表", subtitle: monthStr, lines: lines, fileName: fileName)
    }

    // MARK: - 年度报告

    static func annualReport(year: Int) async throws -> URL {
        let service = CloudKitService.shared
        let rooms = try await service.fetchAllRooms()
        let totalRooms = rooms.count
        let totalMonthlyCost = rooms.reduce(0) { $0 + $1.monthlyCost }
        let roomMap = Dictionary(uniqueKeysWithValues: rooms.map { ($0.id, $0) })

        var monthlyData: [(month: Int, revenue: Double, nights: Int, checkouts: Int)] = []
        var yearRevenue = 0.0
        var yearNights = 0
        var yearCheckouts = 0
        var yearTypeStats: [String: (count: Int, revenue: Double, nights: Int)] = [:]
        var yearGuestData: [String: (name: String, phone: String, count: Int, total: Double)] = [:]

        for month in 1...12 {
            let reservations = try await service.fetchReservationsForMonth(year: year, month: month)
            let revenue = reservations.reduce(0) { $0 + $1.totalRevenue }
            let nights = reservations.reduce(0) { $0 + $1.nightsStayed }

            monthlyData.append((month: month, revenue: revenue, nights: nights, checkouts: reservations.count))
            yearRevenue += revenue
            yearNights += nights
            yearCheckouts += reservations.count

            // 房型统计
            for res in reservations {
                let typeName = roomMap[res.roomID]?.roomType.rawValue ?? "未知"
                let existing = yearTypeStats[typeName] ?? (count: 0, revenue: 0, nights: 0)
                yearTypeStats[typeName] = (count: existing.count + 1, revenue: existing.revenue + res.totalRevenue, nights: existing.nights + res.nightsStayed)
            }

            // 客人统计
            for res in reservations {
                let name = res.guest?.name ?? "未知"
                let phone = Validators.maskedPhone(res.guest?.phone ?? "")
                let existing = yearGuestData[res.guestID] ?? (name: name, phone: phone, count: 0, total: 0)
                yearGuestData[res.guestID] = (name: name, phone: phone, count: existing.count + 1, total: existing.total + res.totalRevenue)
            }
        }

        let yearCost = totalMonthlyCost * 12
        let yearProfit = yearRevenue - yearCost
        let yearADR = yearNights > 0 ? yearRevenue / Double(yearNights) : 0
        let yearTitle = "\(year)年度"
        let fileName = "年度报告_\(year)"

        var lines: [(String, String)] = [
            ("报告年份", yearTitle),
            ("总房间数", "\(totalRooms) 间"),
            ("", ""),
            ("══════════════════════════", ""),
            ("【年度经营总览】", ""),
            ("══════════════════════════", ""),
            ("年度总营收", "¥\(formatMoney(yearRevenue))"),
            ("年度总成本", "¥\(formatMoney(yearCost))"),
            ("年度净利润", "¥\(formatMoney(yearProfit))"),
            ("利润率", yearRevenue > 0 ? String(format: "%.1f%%", yearProfit / yearRevenue * 100) : "N/A"),
            ("", ""),
            ("总退房笔数", "\(yearCheckouts) 笔"),
            ("总间夜数", "\(yearNights) 晚"),
            ("全年平均房价(ADR)", "¥\(formatMoney(yearADR))"),
            ("全年 RevPAR", totalRooms > 0 ? "¥\(formatMoney(yearRevenue / Double(totalRooms)))" : "0"),
            ("", ""),
            ("══════════════════════════", ""),
            ("【月度趋势】", ""),
            ("══════════════════════════", ""),
        ]

        // 月度明细
        let monthNames = ["1月","2月","3月","4月","5月","6月","7月","8月","9月","10月","11月","12月"]
        let bestMonth = monthlyData.max(by: { $0.revenue < $1.revenue })
        let worstMonth = monthlyData.filter { $0.revenue > 0 }.min(by: { $0.revenue < $1.revenue })

        for md in monthlyData {
            let monthCost = totalMonthlyCost
            let monthProfit = md.revenue - monthCost
            let marker = md.month == bestMonth?.month ? " ★最佳" : (md.month == worstMonth?.month && md.revenue > 0 ? " ▼最低" : "")
            lines.append(("  \(monthNames[md.month - 1])", "¥\(formatMoney(md.revenue)) | \(md.checkouts)笔 | \(md.nights)晚 | 利润¥\(formatMoney(monthProfit))\(marker)"))
        }

        // 季度汇总
        lines.append(("", ""))
        lines.append(("══════════════════════════", ""))
        lines.append(("【季度汇总】", ""))
        lines.append(("══════════════════════════", ""))
        let quarters = [(1...3, "Q1 春季"), (4...6, "Q2 夏季"), (7...9, "Q3 秋季"), (10...12, "Q4 冬季")]
        for (range, name) in quarters {
            let qData = monthlyData.filter { range.contains($0.month) }
            let qRevenue = qData.reduce(0) { $0 + $1.revenue }
            let qNights = qData.reduce(0) { $0 + $1.nights }
            let qCost = totalMonthlyCost * 3
            lines.append(("  \(name)", "营收¥\(formatMoney(qRevenue)) | \(qNights)晚 | 利润¥\(formatMoney(qRevenue - qCost))"))
        }

        // 房型分析
        lines.append(("", ""))
        lines.append(("══════════════════════════", ""))
        lines.append(("【房型年度分析】", ""))
        lines.append(("══════════════════════════", ""))
        for (type, data) in yearTypeStats.sorted(by: { $0.value.revenue > $1.value.revenue }) {
            let adr = data.nights > 0 ? data.revenue / Double(data.nights) : 0
            lines.append(("  \(type)", "\(data.count)笔 | \(data.nights)晚 | ¥\(formatMoney(data.revenue)) | 均价¥\(Int(adr))"))
        }

        // TOP 20 客人
        let topGuests = yearGuestData.values.sorted { $0.total > $1.total }.prefix(20)
        lines.append(("", ""))
        lines.append(("══════════════════════════", ""))
        lines.append(("【年度 TOP 20 客源】", ""))
        lines.append(("══════════════════════════", ""))
        for (i, guest) in topGuests.enumerated() {
            lines.append(("  \(i + 1). \(guest.name)", "\(guest.count)次 | ¥\(formatMoney(guest.total))"))
        }

        // 统计
        let uniqueGuests = yearGuestData.count
        let repeatGuests = yearGuestData.values.filter { $0.count > 1 }.count
        lines.append(("", ""))
        lines.append(("══════════════════════════", ""))
        lines.append(("【客源统计】", ""))
        lines.append(("══════════════════════════", ""))
        lines.append(("年度客人总数", "\(uniqueGuests) 人"))
        lines.append(("回头客", "\(repeatGuests) 人（\(uniqueGuests > 0 ? String(format: "%.1f%%", Double(repeatGuests) / Double(uniqueGuests) * 100) : "0%")）"))
        lines.append(("客均消费", uniqueGuests > 0 ? "¥\(formatMoney(yearRevenue / Double(uniqueGuests)))" : "0"))

        return generatePDF(title: "年度经营报告", subtitle: yearTitle, lines: lines, fileName: fileName)
    }

    // MARK: - PDF 生成

    private static func generatePDF(title: String, subtitle: String, lines: [(String, String)], fileName: String) -> URL {
        let pageWidth: CGFloat = 595  // A4
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 50

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            // 标题
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 22),
                .foregroundColor: UIColor.black
            ]
            let titleStr = NSAttributedString(string: title, attributes: titleAttr)
            titleStr.draw(at: CGPoint(x: margin, y: y))
            y += 32

            // 副标题
            let subtitleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 14),
                .foregroundColor: UIColor.darkGray
            ]
            let subtitleStr = NSAttributedString(string: subtitle + "  |  生成时间: \(formatDate(Date(), format: "yyyy-MM-dd HH:mm"))")
            let styledSubtitle = NSAttributedString(string: subtitleStr.string, attributes: subtitleAttr)
            styledSubtitle.draw(at: CGPoint(x: margin, y: y))
            y += 24

            // 分隔线
            context.cgContext.setStrokeColor(UIColor.lightGray.cgColor)
            context.cgContext.setLineWidth(0.5)
            context.cgContext.move(to: CGPoint(x: margin, y: y))
            context.cgContext.addLine(to: CGPoint(x: pageWidth - margin, y: y))
            context.cgContext.strokePath()
            y += 16

            // 内容
            let labelAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 13),
                .foregroundColor: UIColor.darkGray
            ]
            let valueAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 13),
                .foregroundColor: UIColor.black
            ]
            let sectionAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 1)
            ]

            for (label, value) in lines {
                // 检查是否需要换页
                if y > pageHeight - margin - 30 {
                    context.beginPage()
                    y = margin
                }

                if label.isEmpty && value.isEmpty {
                    y += 8
                    continue
                }

                if label.hasPrefix("【") {
                    NSAttributedString(string: label, attributes: sectionAttr)
                        .draw(at: CGPoint(x: margin, y: y))
                    y += 22
                } else {
                    NSAttributedString(string: label, attributes: labelAttr)
                        .draw(at: CGPoint(x: margin, y: y))
                    if !value.isEmpty {
                        let valueStr = NSAttributedString(string: value, attributes: valueAttr)
                        let valueSize = valueStr.size()
                        valueStr.draw(at: CGPoint(x: pageWidth - margin - valueSize.width, y: y))
                    }
                    y += 20
                }
            }

            // 页脚
            y = pageHeight - margin
            let footerAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 10),
                .foregroundColor: UIColor.lightGray
            ]
            NSAttributedString(string: "酒店前台管理系统 · \(title)", attributes: footerAttr)
                .draw(at: CGPoint(x: margin, y: y))
        }

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(fileName).pdf")
        try? data.write(to: url)
        return url
    }

    // MARK: - 辅助

    private static func formatDate(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.dateFormat = format
        return f.string(from: date)
    }

    private static func formatMoney(_ value: Double) -> String {
        if abs(value) >= 10000 {
            return String(format: "%.1f万", value / 10000)
        }
        return String(format: "%.0f", value)
    }
}
