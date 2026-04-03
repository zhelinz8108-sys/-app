import UIKit
import PDFKit

/// 收据/发票生成器 — 生成 PDF 格式的客人收据
@MainActor
enum InvoiceGenerator {

    // MARK: - 酒店信息配置

    struct HotelInfo {
        let name: String
        let address: String
        let phone: String

        static var current: HotelInfo {
            let defaults = UserDefaults.standard
            return HotelInfo(
                name: defaults.string(forKey: "hotelName") ?? "酒店前台管理系统",
                address: defaults.string(forKey: "hotelAddress") ?? "",
                phone: defaults.string(forKey: "hotelPhone") ?? ""
            )
        }
    }

    // MARK: - 生成收据

    /// 根据入住记录和押金记录生成 PDF 收据
    /// - Parameters:
    ///   - reservation: 入住记录（需已填充 guest 和 room）
    ///   - depositRecords: 该入住记录的所有押金操作
    ///   - hotelInfo: 酒店信息，默认从 UserDefaults 读取
    /// - Returns: PDF 文件的临时 URL
    static func generateInvoice(
        reservation: Reservation,
        depositRecords: [DepositRecord],
        hotelInfo: HotelInfo = .current
    ) -> URL {
        let pageWidth: CGFloat = 595  // A4
        let pageHeight: CGFloat = 842
        let margin: CGFloat = 50
        let contentWidth = pageWidth - margin * 2

        // 收据编号
        let invoiceNumber = generateInvoiceNumber(reservationID: reservation.id)
        let issueDate = Date()

        // 财务计算
        let summary = DepositSummary(records: depositRecords)
        let roomCharge = reservation.totalRevenue
        let depositCollected = summary.totalCollected
        let depositRefunded = summary.totalRefunded
        let depositBalance = summary.balance  // 未退还的押金
        // 应退 = 押金余额 - 房费（如果押金 > 房费）；应补 = 房费 - 押金收取（如果房费 > 押金）
        let netBalance = depositCollected - depositRefunded - roomCharge

        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))

        let data = renderer.pdfData { context in
            context.beginPage()
            var y: CGFloat = margin

            // ═══════ 酒店名称（大标题）═══════
            let hotelNameAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            let hotelNameStr = NSAttributedString(string: hotelInfo.name, attributes: hotelNameAttr)
            let hotelNameSize = hotelNameStr.size()
            hotelNameStr.draw(at: CGPoint(x: (pageWidth - hotelNameSize.width) / 2, y: y))
            y += 34

            // 酒店地址和电话（居中）
            if !hotelInfo.address.isEmpty || !hotelInfo.phone.isEmpty {
                let infoAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 11),
                    .foregroundColor: UIColor.gray
                ]
                var infoText = ""
                if !hotelInfo.address.isEmpty { infoText += hotelInfo.address }
                if !hotelInfo.phone.isEmpty {
                    if !infoText.isEmpty { infoText += "  |  " }
                    infoText += "电话: \(hotelInfo.phone)"
                }
                let infoStr = NSAttributedString(string: infoText, attributes: infoAttr)
                let infoSize = infoStr.size()
                infoStr.draw(at: CGPoint(x: (pageWidth - infoSize.width) / 2, y: y))
                y += 20
            }

            // ═══════ "住宿收据" 标题 ═══════
            y += 4
            let titleAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor(red: 0.2, green: 0.2, blue: 0.2, alpha: 1)
            ]
            let titleStr = NSAttributedString(string: "住 宿 收 据", attributes: titleAttr)
            let titleSize = titleStr.size()
            titleStr.draw(at: CGPoint(x: (pageWidth - titleSize.width) / 2, y: y))
            y += 30

            // 分隔线（双线）
            drawDoubleLine(context: context.cgContext, y: y, left: margin, right: pageWidth - margin)
            y += 10

            // ═══════ 收据信息行 ═══════
            let labelFont = UIFont.systemFont(ofSize: 11)
            let valueFont = UIFont.boldSystemFont(ofSize: 11)
            let labelColor = UIColor.darkGray
            let valueColor = UIColor.black

            // 收据号 + 开具日期（同一行）
            drawKeyValue(at: CGPoint(x: margin, y: y),
                        label: "收据编号:", value: invoiceNumber,
                        labelFont: labelFont, valueFont: valueFont,
                        labelColor: labelColor, valueColor: valueColor)
            let dateStr = formatDate(issueDate, format: "yyyy年M月d日 HH:mm")
            drawKeyValueRight(at: CGPoint(x: pageWidth - margin, y: y),
                             label: "开具日期:", value: dateStr,
                             labelFont: labelFont, valueFont: valueFont,
                             labelColor: labelColor, valueColor: valueColor)
            y += 22

            // 薄分隔线
            drawLine(context: context.cgContext, y: y, left: margin, right: pageWidth - margin, color: .lightGray)
            y += 12

            // ═══════ 客人信息 ═══════
            let sectionFont = UIFont.boldSystemFont(ofSize: 13)
            let sectionColor = UIColor(red: 0.15, green: 0.35, blue: 0.65, alpha: 1)

            NSAttributedString(string: "客人信息", attributes: [.font: sectionFont, .foregroundColor: sectionColor])
                .draw(at: CGPoint(x: margin, y: y))
            y += 22

            let guestName = reservation.guest?.name ?? "未知"
            let guestPhone = reservation.guest?.phone ?? ""
            let roomNumber = reservation.room?.roomNumber ?? "未知"
            let roomType = reservation.room?.roomType.rawValue ?? ""

            drawKeyValue(at: CGPoint(x: margin, y: y),
                        label: "客人姓名:", value: guestName,
                        labelFont: labelFont, valueFont: valueFont,
                        labelColor: labelColor, valueColor: valueColor)
            if !guestPhone.isEmpty {
                drawKeyValue(at: CGPoint(x: margin + contentWidth / 2, y: y),
                            label: "联系电话:", value: Validators.maskedPhone(guestPhone),
                            labelFont: labelFont, valueFont: valueFont,
                            labelColor: labelColor, valueColor: valueColor)
            }
            y += 20

            drawKeyValue(at: CGPoint(x: margin, y: y),
                        label: "房间号:", value: "\(roomNumber) (\(roomType))",
                        labelFont: labelFont, valueFont: valueFont,
                        labelColor: labelColor, valueColor: valueColor)
            drawKeyValue(at: CGPoint(x: margin + contentWidth / 2, y: y),
                        label: "入住人数:", value: "\(reservation.numberOfGuests) 人",
                        labelFont: labelFont, valueFont: valueFont,
                        labelColor: labelColor, valueColor: valueColor)
            y += 22

            // 薄分隔线
            drawLine(context: context.cgContext, y: y, left: margin, right: pageWidth - margin, color: .lightGray)
            y += 12

            // ═══════ 住宿明细 ═══════
            NSAttributedString(string: "住宿明细", attributes: [.font: sectionFont, .foregroundColor: sectionColor])
                .draw(at: CGPoint(x: margin, y: y))
            y += 22

            let checkInStr = formatDate(reservation.checkInDate, format: "yyyy年M月d日")
            let checkOutDate = reservation.actualCheckOut ?? reservation.expectedCheckOut
            let checkOutStr = formatDate(checkOutDate, format: "yyyy年M月d日")

            drawKeyValue(at: CGPoint(x: margin, y: y),
                        label: "入住日期:", value: checkInStr,
                        labelFont: labelFont, valueFont: valueFont,
                        labelColor: labelColor, valueColor: valueColor)
            drawKeyValue(at: CGPoint(x: margin + contentWidth / 2, y: y),
                        label: "退房日期:", value: checkOutStr,
                        labelFont: labelFont, valueFont: valueFont,
                        labelColor: labelColor, valueColor: valueColor)
            y += 22

            // 表格头
            let tableHeaderAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 11),
                .foregroundColor: UIColor.white
            ]
            let headerBg = UIColor(red: 0.25, green: 0.45, blue: 0.75, alpha: 1)

            // 表格背景
            let tableLeft = margin
            let tableRight = pageWidth - margin
            let colWidths: [CGFloat] = [contentWidth * 0.40, contentWidth * 0.20, contentWidth * 0.20, contentWidth * 0.20]
            let rowHeight: CGFloat = 24

            // 绘制表头背景
            context.cgContext.setFillColor(headerBg.cgColor)
            context.cgContext.fill(CGRect(x: tableLeft, y: y, width: contentWidth, height: rowHeight))

            let headers = ["项目", "数量", "单价", "金额"]
            var colX = tableLeft
            for (i, header) in headers.enumerated() {
                let str = NSAttributedString(string: header, attributes: tableHeaderAttr)
                let xOffset: CGFloat = i == 0 ? 8 : (colWidths[i] - str.size().width) / 2
                str.draw(at: CGPoint(x: colX + xOffset, y: y + 4))
                colX += colWidths[i]
            }
            y += rowHeight

            // 表格行：房费
            let cellAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.black
            ]
            let cellBoldAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 11),
                .foregroundColor: UIColor.black
            ]

            // 斑马纹背景
            context.cgContext.setFillColor(UIColor(white: 0.96, alpha: 1).cgColor)
            context.cgContext.fill(CGRect(x: tableLeft, y: y, width: contentWidth, height: rowHeight))

            let nightsStayed = reservation.nightsStayed
            let dailyRate = reservation.dailyRate > 0 ? reservation.dailyRate : (reservation.room?.pricePerNight ?? 0)

            let rowValues = [
                "\(roomType)住宿",
                "\(nightsStayed) 晚",
                "¥\(formatMoney(dailyRate))",
                "¥\(formatMoney(roomCharge))"
            ]
            colX = tableLeft
            for (i, val) in rowValues.enumerated() {
                let attr = i == 3 ? cellBoldAttr : cellAttr
                let str = NSAttributedString(string: val, attributes: attr)
                let xOffset: CGFloat = i == 0 ? 8 : (colWidths[i] - str.size().width) / 2
                str.draw(at: CGPoint(x: colX + xOffset, y: y + 4))
                colX += colWidths[i]
            }
            y += rowHeight

            // 表格底线
            drawLine(context: context.cgContext, y: y, left: tableLeft, right: tableRight, color: headerBg)
            y += 16

            // ═══════ 费用汇总 ═══════
            NSAttributedString(string: "费用汇总", attributes: [.font: sectionFont, .foregroundColor: sectionColor])
                .draw(at: CGPoint(x: margin, y: y))
            y += 22

            let summaryLabelFont = UIFont.systemFont(ofSize: 12)
            let summaryValueFont = UIFont.boldSystemFont(ofSize: 12)

            // 房费合计
            drawSummaryRow(y: y, left: margin, right: pageWidth - margin,
                          label: "房费合计", value: "¥\(formatMoney(roomCharge))",
                          labelFont: summaryLabelFont, valueFont: summaryValueFont,
                          labelColor: labelColor, valueColor: valueColor)
            y += 22

            // 押金收取
            if depositCollected > 0 {
                drawSummaryRow(y: y, left: margin, right: pageWidth - margin,
                              label: "押金收取", value: "¥\(formatMoney(depositCollected))",
                              labelFont: summaryLabelFont, valueFont: summaryValueFont,
                              labelColor: labelColor, valueColor: .blue)
                y += 20

                // 押金退还明细
                let refundRecords = depositRecords.filter { $0.type == .refund }
                for record in refundRecords {
                    let methodStr = record.paymentMethod.rawValue
                    let timeStr = formatDate(record.timestamp, format: "M月d日 HH:mm")
                    drawSummaryRow(y: y, left: margin + 20, right: pageWidth - margin,
                                  label: "  退还(\(methodStr) \(timeStr))",
                                  value: "-¥\(formatMoney(record.amount))",
                                  labelFont: UIFont.systemFont(ofSize: 10),
                                  valueFont: UIFont.systemFont(ofSize: 10),
                                  labelColor: .gray, valueColor: UIColor(red: 0, green: 0.6, blue: 0, alpha: 1))
                    y += 18
                }

                if depositBalance > 0 {
                    drawSummaryRow(y: y, left: margin, right: pageWidth - margin,
                                  label: "押金余额（未退还）", value: "¥\(formatMoney(depositBalance))",
                                  labelFont: summaryLabelFont, valueFont: summaryValueFont,
                                  labelColor: .orange, valueColor: .orange)
                    y += 22
                }
            }

            // 收款方式汇总
            let collectRecords = depositRecords.filter { $0.type == .collect }
            if !collectRecords.isEmpty {
                let methods = Dictionary(grouping: collectRecords, by: { $0.paymentMethod })
                let methodSummary = methods.map { "\($0.key.rawValue) ¥\(formatMoney($0.value.reduce(0) { $0 + $1.amount }))" }
                    .joined(separator: "、")
                drawSummaryRow(y: y, left: margin, right: pageWidth - margin,
                              label: "支付方式", value: methodSummary,
                              labelFont: UIFont.systemFont(ofSize: 10), valueFont: UIFont.systemFont(ofSize: 10),
                              labelColor: .gray, valueColor: .darkGray)
                y += 22
            }

            // 粗分隔线
            drawLine(context: context.cgContext, y: y, left: margin, right: pageWidth - margin, color: .darkGray, width: 1.0)
            y += 12

            // ═══════ 结算金额（醒目）═══════
            let totalLabelAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 16),
                .foregroundColor: UIColor.black
            ]

            if netBalance > 0 {
                // 押金有余额，应退给客人
                let totalStr = NSAttributedString(string: "应退客人:", attributes: totalLabelAttr)
                totalStr.draw(at: CGPoint(x: margin, y: y))
                let amountAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor(red: 0, green: 0.6, blue: 0, alpha: 1)
                ]
                let amountStr = NSAttributedString(string: "¥\(formatMoney(netBalance))", attributes: amountAttr)
                let amountSize = amountStr.size()
                amountStr.draw(at: CGPoint(x: pageWidth - margin - amountSize.width, y: y - 2))
            } else if netBalance < 0 {
                // 客人需补款
                let totalStr = NSAttributedString(string: "客人应补:", attributes: totalLabelAttr)
                totalStr.draw(at: CGPoint(x: margin, y: y))
                let amountAttr: [NSAttributedString.Key: Any] = [
                    .font: UIFont.boldSystemFont(ofSize: 20),
                    .foregroundColor: UIColor.red
                ]
                let amountStr = NSAttributedString(string: "¥\(formatMoney(abs(netBalance)))", attributes: amountAttr)
                let amountSize = amountStr.size()
                amountStr.draw(at: CGPoint(x: pageWidth - margin - amountSize.width, y: y - 2))
            } else {
                // 刚好结清
                let totalStr = NSAttributedString(string: "已结清", attributes: [
                    .font: UIFont.boldSystemFont(ofSize: 16),
                    .foregroundColor: UIColor(red: 0, green: 0.6, blue: 0, alpha: 1)
                ])
                let totalSize = totalStr.size()
                totalStr.draw(at: CGPoint(x: (pageWidth - totalSize.width) / 2, y: y))
            }
            y += 36

            // ═══════ 页脚 ═══════
            // 分隔线
            drawDoubleLine(context: context.cgContext, y: pageHeight - margin - 40, left: margin, right: pageWidth - margin)

            let footerAttr: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 9),
                .foregroundColor: UIColor.lightGray
            ]
            let footerLines = [
                "本收据由系统自动生成，如有疑问请联系前台。",
                "收据编号: \(invoiceNumber)  |  生成时间: \(formatDate(issueDate, format: "yyyy-MM-dd HH:mm:ss"))"
            ]
            var footerY = pageHeight - margin - 30
            for line in footerLines {
                let str = NSAttributedString(string: line, attributes: footerAttr)
                let strSize = str.size()
                str.draw(at: CGPoint(x: (pageWidth - strSize.width) / 2, y: footerY))
                footerY += 14
            }
        }

        let fileName = "收据_\(reservation.room?.roomNumber ?? "未知")_\(formatDate(Date(), format: "yyyyMMdd_HHmmss"))"
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("\(fileName).pdf")
        try? SecureStorageHelper.write(data, to: url, excludeFromBackup: true)
        return url
    }

    // MARK: - 为历史记录生成收据（需从服务加载押金）

    /// 为已退房的历史记录生成收据
    static func generateInvoiceForHistory(reservation: Reservation) async throws -> URL {
        let deposits = try await CloudKitService.shared.fetchDeposits(forReservationID: reservation.id)
        return generateInvoice(reservation: reservation, depositRecords: deposits)
    }

    // MARK: - 收据编号生成

    private static func generateInvoiceNumber(reservationID: String) -> String {
        let dateStr = formatDate(Date(), format: "yyyyMMddHHmmss")
        let suffix = String(reservationID.suffix(4))
        return "INV-\(dateStr)-\(suffix)"
    }

    // MARK: - 绘图辅助

    private static func drawKeyValue(
        at point: CGPoint,
        label: String, value: String,
        labelFont: UIFont, valueFont: UIFont,
        labelColor: UIColor, valueColor: UIColor
    ) {
        let labelStr = NSAttributedString(string: label, attributes: [.font: labelFont, .foregroundColor: labelColor])
        let valueStr = NSAttributedString(string: value, attributes: [.font: valueFont, .foregroundColor: valueColor])
        labelStr.draw(at: point)
        valueStr.draw(at: CGPoint(x: point.x + labelStr.size().width + 4, y: point.y))
    }

    private static func drawKeyValueRight(
        at point: CGPoint,
        label: String, value: String,
        labelFont: UIFont, valueFont: UIFont,
        labelColor: UIColor, valueColor: UIColor
    ) {
        let labelStr = NSAttributedString(string: label, attributes: [.font: labelFont, .foregroundColor: labelColor])
        let valueStr = NSAttributedString(string: value, attributes: [.font: valueFont, .foregroundColor: valueColor])
        let totalWidth = labelStr.size().width + 4 + valueStr.size().width
        let startX = point.x - totalWidth
        labelStr.draw(at: CGPoint(x: startX, y: point.y))
        valueStr.draw(at: CGPoint(x: startX + labelStr.size().width + 4, y: point.y))
    }

    private static func drawSummaryRow(
        y: CGFloat, left: CGFloat, right: CGFloat,
        label: String, value: String,
        labelFont: UIFont, valueFont: UIFont,
        labelColor: UIColor, valueColor: UIColor
    ) {
        let labelStr = NSAttributedString(string: label, attributes: [.font: labelFont, .foregroundColor: labelColor])
        labelStr.draw(at: CGPoint(x: left, y: y))
        let valueStr = NSAttributedString(string: value, attributes: [.font: valueFont, .foregroundColor: valueColor])
        let valueSize = valueStr.size()
        valueStr.draw(at: CGPoint(x: right - valueSize.width, y: y))
    }

    private static func drawLine(context: CGContext, y: CGFloat, left: CGFloat, right: CGFloat, color: UIColor, width: CGFloat = 0.5) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.move(to: CGPoint(x: left, y: y))
        context.addLine(to: CGPoint(x: right, y: y))
        context.strokePath()
    }

    private static func drawDoubleLine(context: CGContext, y: CGFloat, left: CGFloat, right: CGFloat) {
        let color = UIColor.darkGray.cgColor
        context.setStrokeColor(color)
        context.setLineWidth(0.8)
        context.move(to: CGPoint(x: left, y: y))
        context.addLine(to: CGPoint(x: right, y: y))
        context.strokePath()
        context.move(to: CGPoint(x: left, y: y + 2.5))
        context.addLine(to: CGPoint(x: right, y: y + 2.5))
        context.strokePath()
    }

    // MARK: - 格式化辅助

    private static func formatDate(_ date: Date, format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = format
        return f.string(from: date)
    }

    private static func formatMoney(_ value: Double) -> String {
        if value == Double(Int(value)) {
            return String(format: "%.0f", value)
        }
        return String(format: "%.2f", value)
    }
}
