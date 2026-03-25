import SwiftUI
import UIKit
@preconcurrency import Vision

/// OTA 订单录入表单
struct OTABookingFormView: View {
    @ObservedObject private var bookingService = OTABookingService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var platform: OTAPlatform = .meituan
    @State private var customPlatformName = ""
    @State private var orderID = ""
    @State private var guestName = ""
    @State private var guestPhone = ""
    @State private var roomType: RoomType = .king
    @State private var checkInDate = Date()
    @State private var nights = 1
    @State private var price = ""
    @State private var notes = ""
    @State private var showCameraPicker = false
    @State private var showPhotoPicker = false
    @State private var isRecognizingImage = false
    @State private var recognitionFeedbackMessage = ""
    @State private var showRecognitionFeedback = false
    @State private var recognitionNotice: String?
    @State private var recognitionNoticeIsError = false

    private let logService = OperationLogService.shared

    private let colorMap: [String: Color] = [
        "yellow": .yellow,
        "orange": .orange,
        "blue": .blue,
        "indigo": .indigo,
        "red": .red,
        "green": .green,
        "gray": .gray
    ]

    private var trimmedGuestName: String {
        guestName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedCustomPlatformName: String {
        customPlatformName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedOrderID: String {
        orderID.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedPlatformDisplayName: String {
        if platform == .other, !trimmedCustomPlatformName.isEmpty {
            return trimmedCustomPlatformName
        }

        return platform.rawValue
    }

    private var isSaveDisabled: Bool {
        trimmedGuestName.isEmpty
            || (Double(price) ?? 0) <= 0
            || (platform == .other && trimmedCustomPlatformName.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("来源平台") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(OTAPlatform.allCases) { currentPlatform in
                                Button {
                                    platform = currentPlatform
                                } label: {
                                    VStack(spacing: 4) {
                                        Image(systemName: currentPlatform.icon)
                                            .font(.title3)
                                        Text(currentPlatform.rawValue)
                                            .font(.caption)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(2)
                                    }
                                    .frame(width: 64, height: 58)
                                    .background(
                                        platform == currentPlatform
                                        ? (colorMap[currentPlatform.color] ?? .gray).opacity(0.2)
                                        : Color(.tertiarySystemFill)
                                    )
                                    .foregroundStyle(
                                        platform == currentPlatform
                                        ? (colorMap[currentPlatform.color] ?? .gray)
                                        : .secondary
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }

                    if platform == .other {
                        HStack {
                            Text("其他平台")
                            Spacer()
                            TextField("如：同程、去哪儿、Airbnb", text: $customPlatformName)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("可直接拍电脑上的 OTA 预订单，或上传手机截图自动识别填入。")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button {
                                showCameraPicker = true
                            } label: {
                                Label("拍照识别", systemImage: "camera.viewfinder")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue.opacity(0.12))
                                    .foregroundStyle(.blue)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }

                            Button {
                                showPhotoPicker = true
                            } label: {
                                Label("上传图片", systemImage: "photo.on.rectangle")
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .frame(maxWidth: .infinity)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.vertical, 4)

                    HStack {
                        Text("平台订单号")
                        Spacer()
                        TextField("选填", text: $orderID)
                            .multilineTextAlignment(.trailing)
                            .textInputAutocapitalization(.never)
                    }
                    HStack {
                        Text("客人姓名")
                        Spacer()
                        TextField("必填", text: $guestName)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("联系电话")
                        Spacer()
                        TextField("选填", text: $guestPhone)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.phonePad)
                    }
                } header: {
                    Text("订单信息")
                } footer: {
                    if let recognitionNotice {
                        Text(recognitionNotice)
                            .foregroundStyle(recognitionNoticeIsError ? .red : .secondary)
                    }
                }

                Section("入住信息") {
                    Picker("房型", selection: $roomType) {
                        ForEach(RoomType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    DatePicker("入住日期", selection: $checkInDate, displayedComponents: .date)

                    Stepper("住 \(nights) 晚", value: $nights, in: 1...30)

                    HStack {
                        Text("退房日期")
                        Spacer()
                        let checkOut = Calendar.current.date(byAdding: .day, value: nights, to: checkInDate) ?? checkInDate
                        Text(checkOut.chineseDate)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("价格") {
                    HStack {
                        Text("每晚价格 ¥")
                        TextField("OTA结算价", text: $price)
                            .keyboardType(.decimalPad)
                    }
                    if let priceValue = Double(price), priceValue > 0 {
                        HStack {
                            Text("合计")
                            Spacer()
                            Text("¥\(formatMoney(priceValue * Double(nights)))（\(nights)晚）")
                                .fontWeight(.bold)
                                .foregroundStyle(.blue)
                        }
                    }
                }

                Section("备注（选填）") {
                    TextField("如：客人要求高楼层、加床等", text: $notes)
                }
            }
            .navigationTitle("录入 OTA 订单")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("确认") {
                        saveBooking()
                    }
                    .fontWeight(.bold)
                    .disabled(isSaveDisabled)
                }
            }
            .onChange(of: platform) { _, newValue in
                if newValue != .other {
                    customPlatformName = ""
                }
            }
            .fullScreenCover(isPresented: $showCameraPicker) {
                ImagePickerView(sourceType: .camera) { image in
                    recognizeBookingImage(image)
                }
            }
            .sheet(isPresented: $showPhotoPicker) {
                ImagePickerView(sourceType: .photoLibrary) { image in
                    recognizeBookingImage(image)
                }
            }
            .overlay {
                if isRecognizingImage {
                    ZStack {
                        Color.black.opacity(0.12)
                            .ignoresSafeArea()

                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.15)
                            Text("正在识别订单图片…")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("识别后会自动填入表单，请再核对一遍。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(radius: 18)
                    }
                }
            }
            .alert("订单图片识别", isPresented: $showRecognitionFeedback) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text(recognitionFeedbackMessage)
            }
        }
    }

    private func recognizeBookingImage(_ image: UIImage) {
        isRecognizingImage = true
        recognitionNotice = nil
        recognitionNoticeIsError = false

        Task {
            do {
                let result = try await OTABookingImageRecognizer.recognize(image: image)
                await MainActor.run {
                    applyRecognitionResult(result)
                    isRecognizingImage = false
                }
            } catch {
                await MainActor.run {
                    isRecognizingImage = false
                    recognitionNotice = error.localizedDescription
                    recognitionNoticeIsError = true
                    recognitionFeedbackMessage = error.localizedDescription
                    showRecognitionFeedback = true
                }
            }
        }
    }

    private func applyRecognitionResult(_ result: OTABookingAutofillData) {
        var updatedFields: [String] = []

        if let recognizedPlatform = result.platform {
            platform = recognizedPlatform
            updatedFields.append("平台")

            if recognizedPlatform == .other {
                customPlatformName = result.customPlatformName ?? customPlatformName
            } else {
                customPlatformName = ""
            }
        }

        if let platformOrderID = result.platformOrderID, !platformOrderID.isEmpty {
            orderID = platformOrderID
            updatedFields.append("订单号")
        }

        if let guestName = result.guestName, !guestName.isEmpty {
            self.guestName = guestName
            updatedFields.append("客人姓名")
        }

        if let guestPhone = result.guestPhone, !guestPhone.isEmpty {
            self.guestPhone = guestPhone
            updatedFields.append("联系电话")
        }

        if let roomType = result.roomType {
            self.roomType = roomType
            updatedFields.append("房型")
        }

        if let checkInDate = result.checkInDate {
            self.checkInDate = checkInDate
            updatedFields.append("入住日期")
        }

        if let nights = result.nights, nights >= 1 {
            self.nights = nights
            updatedFields.append("住店晚数")
        }

        if let nightlyPrice = result.nightlyPrice, nightlyPrice > 0 {
            price = formatPriceInput(nightlyPrice)
            updatedFields.append("每晚价格")
        }

        let uniqueUpdatedFields = Array(NSOrderedSet(array: updatedFields)) as? [String] ?? updatedFields

        if uniqueUpdatedFields.isEmpty {
            recognitionNotice = "图片里识别到了文字，但没能定位出可填入的 OTA 订单字段，请手动补充。"
            recognitionNoticeIsError = true
        } else {
            recognitionNotice = "已自动填入：\(uniqueUpdatedFields.joined(separator: "、"))。请核对后再确认。"
            recognitionNoticeIsError = false
        }

        recognitionFeedbackMessage = recognitionNotice ?? "识别完成"
        showRecognitionFeedback = true
    }

    private func saveBooking() {
        guard let priceValue = Double(price) else { return }

        let booking = OTABooking(
            platform: platform,
            customPlatformName: platform == .other ? trimmedCustomPlatformName : nil,
            platformOrderID: trimmedOrderID,
            guestName: trimmedGuestName,
            guestPhone: guestPhone.trimmingCharacters(in: .whitespacesAndNewlines),
            roomType: roomType,
            checkInDate: checkInDate,
            nights: nights,
            price: priceValue,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : notes,
            createdBy: StaffService.shared.currentName
        )
        bookingService.add(booking)

        logService.log(
            type: .checkIn,
            summary: "\(selectedPlatformDisplayName) 预订 \(trimmedGuestName)",
            detail: "平台: \(selectedPlatformDisplayName) | 客人: \(trimmedGuestName) | 房型: \(roomType.rawValue) | \(formatDate(checkInDate))入住\(nights)晚 | ¥\(Int(priceValue))/晚\(trimmedOrderID.isEmpty ? "" : " | 订单号: \(trimmedOrderID)")"
        )

        dismiss()
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func formatMoney(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    private func formatPriceInput(_ value: Double) -> String {
        let roundedValue = (value * 100).rounded() / 100
        if roundedValue.rounded() == roundedValue {
            return String(Int(roundedValue))
        }
        return String(format: "%.2f", roundedValue)
    }
}

struct OTABookingAutofillData {
    var platform: OTAPlatform? = nil
    var customPlatformName: String? = nil
    var platformOrderID: String? = nil
    var guestName: String? = nil
    var guestPhone: String? = nil
    var roomType: RoomType? = nil
    var checkInDate: Date? = nil
    var nights: Int? = nil
    var nightlyPrice: Double? = nil
    var rawText: String

    var recognizedFieldLabels: [String] {
        var labels: [String] = []
        if platform != nil || !(customPlatformName?.isEmpty ?? true) { labels.append("平台") }
        if !(platformOrderID?.isEmpty ?? true) { labels.append("订单号") }
        if !(guestName?.isEmpty ?? true) { labels.append("客人姓名") }
        if !(guestPhone?.isEmpty ?? true) { labels.append("联系电话") }
        if roomType != nil { labels.append("房型") }
        if checkInDate != nil { labels.append("入住日期") }
        if nights != nil { labels.append("住店晚数") }
        if nightlyPrice != nil { labels.append("每晚价格") }
        return labels
    }

    var isEmpty: Bool {
        recognizedFieldLabels.isEmpty
    }
}

enum OTABookingImageRecognizer {
    static func recognize(image: UIImage, referenceDate: Date = Date()) async throws -> OTABookingAutofillData {
        guard let imageData = image.jpegData(compressionQuality: 0.95) ?? image.pngData() else {
            throw OTABookingImageRecognitionError.unreadableImage
        }

        return try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let texts = observations.compactMap { $0.topCandidates(1).first?.string }

                guard !texts.isEmpty else {
                    continuation.resume(throwing: OTABookingImageRecognitionError.noTextFound)
                    return
                }

                let parsed = parseRecognizedTexts(texts, referenceDate: referenceDate)
                guard !parsed.isEmpty else {
                    continuation.resume(throwing: OTABookingImageRecognitionError.noBookingFieldsFound)
                    return
                }

                continuation.resume(returning: parsed)
            }

            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.minimumTextHeight = 0.015

            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let handler = VNImageRequestHandler(data: imageData, options: [:])
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    static func parseRecognizedTexts(_ texts: [String], referenceDate: Date = Date()) -> OTABookingAutofillData {
        let normalizedTexts = texts
            .map(normalizeLine(_:))
            .filter { !$0.isEmpty }

        let rawText = normalizedTexts.joined(separator: "\n")
        var result = OTABookingAutofillData(rawText: rawText)

        let platformMatch = detectPlatform(in: rawText)
        result.platform = platformMatch.platform
        result.customPlatformName = platformMatch.customPlatformName
        result.platformOrderID = extractOrderID(from: normalizedTexts)
        result.guestName = extractGuestName(from: normalizedTexts)
        result.guestPhone = extractPhone(from: normalizedTexts, fullText: rawText)
        result.roomType = extractRoomType(from: rawText)

        let checkInDate = extractLabeledDate(
            from: normalizedTexts,
            labels: ["入住日期", "入住", "check-in", "check in", "arrival", "from"],
            referenceDate: referenceDate
        )
        let checkOutDate = extractLabeledDate(
            from: normalizedTexts,
            labels: ["退房日期", "退房", "离店", "check-out", "check out", "departure", "to"],
            referenceDate: referenceDate
        )

        result.checkInDate = checkInDate
        result.nights = extractNights(from: normalizedTexts, fullText: rawText)

        if result.nights == nil,
           let checkInDate,
           let checkOutDate {
            let start = Calendar.current.startOfDay(for: checkInDate)
            let end = Calendar.current.startOfDay(for: checkOutDate)
            let diff = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
            if diff > 0 {
                result.nights = diff
            }
        }

        result.nightlyPrice = extractNightlyPrice(
            from: normalizedTexts,
            nights: result.nights
        )

        return result
    }

    private static func detectPlatform(in text: String) -> (platform: OTAPlatform?, customPlatformName: String?) {
        let lowercasedText = text.lowercased()
        let mappings: [(keywords: [String], platform: OTAPlatform, customPlatformName: String?)] = [
            (["美团", "meituan"], .meituan, nil),
            (["飞猪", "fliggy"], .fliggy, nil),
            (["携程", "ctrip", "trip.com", "trip com"], .ctrip, nil),
            (["booking", "booking.com"], .booking, nil),
            (["agoda"], .agoda, nil),
            (["同程", "tongcheng"], .other, "同程"),
            (["去哪儿", "qunar"], .other, "去哪儿"),
            (["艺龙", "elong"], .other, "艺龙"),
            (["airbnb"], .other, "Airbnb"),
            (["小猪"], .other, "小猪"),
            (["途家"], .other, "途家"),
            (["电话", "到店", "walk-in", "walk in", "散客"], .direct, nil)
        ]

        for mapping in mappings where mapping.keywords.contains(where: lowercasedText.contains) {
            return (mapping.platform, mapping.customPlatformName)
        }

        return (nil, nil)
    }

    private static func extractOrderID(from texts: [String]) -> String? {
        let labels = [
            "平台订单号", "订单号", "订单编号", "订单id",
            "确认号", "确认编号", "预订号", "预订编号",
            "reservation id", "booking id", "confirmation number", "reference number"
        ]

        if let rawValue = extractLabeledValue(from: texts, labels: labels) {
            return sanitizeOrderID(rawValue)
        }

        return nil
    }

    private static func extractGuestName(from texts: [String]) -> String? {
        let labels = ["客人姓名", "入住人", "联系人", "guest name", "guest", "traveler", "name"]

        if let rawValue = extractLabeledValue(from: texts, labels: labels),
           let sanitizedGuestName = sanitizeGuestName(rawValue) {
            return sanitizedGuestName
        }

        for text in texts {
            if let candidate = firstMatch(in: text, pattern: "[\\p{Han}]{2,4}"),
               !["订单", "房型", "入住", "退房", "平台", "预订", "电话", "联系"].contains(where: candidate.contains) {
                return candidate
            }
        }

        return nil
    }

    private static func extractPhone(from texts: [String], fullText: String) -> String? {
        let labels = ["联系电话", "手机号", "电话", "mobile", "phone", "tel"]

        if let rawValue = extractLabeledValue(from: texts, labels: labels),
           let sanitizedPhone = sanitizePhone(rawValue) {
            return sanitizedPhone
        }

        return sanitizePhone(fullText)
    }

    private static func extractRoomType(from text: String) -> RoomType? {
        let lowercasedText = text.lowercased()

        if ["双床", "标间", "标准间", "twin"].contains(where: lowercasedText.contains) {
            return .twin
        }

        if ["套房", "suite", "family room", "family suite"].contains(where: lowercasedText.contains) {
            return .suite
        }

        if ["大床", "king", "queen", "单床"].contains(where: lowercasedText.contains) {
            return .king
        }

        return nil
    }

    private static func extractLabeledDate(from texts: [String], labels: [String], referenceDate: Date) -> Date? {
        for index in texts.indices {
            let line = texts[index]

            for label in labels {
                if let range = line.range(of: label, options: .caseInsensitive) {
                    let remainder = String(line[range.upperBound...]).trimmedFieldValue

                    if let date = parseDate(from: remainder, referenceDate: referenceDate)
                        ?? parseDate(from: line, referenceDate: referenceDate) {
                        return date
                    }

                    if index + 1 < texts.count,
                       let date = parseDate(from: texts[index + 1], referenceDate: referenceDate) {
                        return date
                    }
                }
            }
        }

        return nil
    }

    private static func extractNights(from texts: [String], fullText: String) -> Int? {
        let patterns = [
            "住\\s*(\\d{1,2})\\s*晚",
            "(\\d{1,2})\\s*晚",
            "(\\d{1,2})\\s*nights?"
        ]

        for text in texts + [fullText] {
            for pattern in patterns {
                if let rawValue = firstMatch(in: text.lowercased(), pattern: pattern),
                   let numericValue = firstMatch(in: rawValue, pattern: "\\d+"),
                   let nights = Int(numericValue),
                   nights >= 1 {
                    return nights
                }
            }
        }

        return nil
    }

    private static func extractNightlyPrice(from texts: [String], nights: Int?) -> Double? {
        let nightlyLabels = ["每晚价格", "单价", "夜价", "房费单价", "ota结算价", "price per night"]
        if let nightlyPrice = extractLabeledAmount(from: texts, labels: nightlyLabels) {
            return nightlyPrice
        }

        let totalLabels = ["总价", "总金额", "总房费", "应付", "实付", "付款金额", "订单总额", "总费用"]
        if let totalPrice = extractLabeledAmount(from: texts, labels: totalLabels),
           let nights,
           nights >= 1 {
            return totalPrice / Double(nights)
        }

        return nil
    }

    private static func extractLabeledValue(from texts: [String], labels: [String]) -> String? {
        for index in texts.indices {
            let line = texts[index]

            for label in labels {
                if let range = line.range(of: label, options: .caseInsensitive) {
                    let remainder = String(line[range.upperBound...]).trimmedFieldValue
                    if !remainder.isEmpty {
                        return remainder
                    }

                    if index + 1 < texts.count {
                        let nextLine = texts[index + 1].trimmedFieldValue
                        if !nextLine.isEmpty {
                            return nextLine
                        }
                    }
                }
            }
        }

        return nil
    }

    private static func extractLabeledAmount(from texts: [String], labels: [String]) -> Double? {
        for index in texts.indices {
            let line = texts[index]

            for label in labels {
                if let range = line.range(of: label, options: .caseInsensitive) {
                    let remainder = String(line[range.upperBound...]).trimmedFieldValue

                    if let amount = extractAmount(from: remainder) ?? extractAmount(from: line) {
                        return amount
                    }

                    if index + 1 < texts.count,
                       let amount = extractAmount(from: texts[index + 1]) {
                        return amount
                    }
                }
            }
        }

        return nil
    }

    private static func extractAmount(from text: String) -> Double? {
        let matches = matches(in: text, pattern: "(?:[¥￥]|rmb|cny)?\\s*(\\d{1,6}(?:\\.\\d{1,2})?)")
            .compactMap { match -> Double? in
                let numericText = firstMatch(in: match, pattern: "\\d{1,6}(?:\\.\\d{1,2})?") ?? match
                return Double(numericText)
            }
            .filter { $0 > 0 }

        return matches.max()
    }

    private static func parseDate(from text: String, referenceDate: Date) -> Date? {
        let datePatterns = [
            "\\d{4}年\\d{1,2}月\\d{1,2}日",
            "\\d{4}[./-]\\d{1,2}[./-]\\d{1,2}",
            "\\d{1,2}月\\d{1,2}日",
            "\\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2},\\s*\\d{4}\\b",
            "\\b(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Sept|Oct|Nov|Dec)[a-z]*\\s+\\d{1,2}\\b",
            "\\b\\d{1,2}/\\d{1,2}/\\d{2,4}\\b",
            "\\b\\d{1,2}/\\d{1,2}\\b"
        ]

        for pattern in datePatterns {
            for candidate in matches(in: text, pattern: pattern) {
                if let date = parseDateCandidate(candidate, referenceDate: referenceDate) {
                    return Calendar.current.startOfDay(for: date)
                }
            }
        }

        return nil
    }

    private static func parseDateCandidate(_ text: String, referenceDate: Date) -> Date? {
        let chineseFormatter = DateFormatter()
        chineseFormatter.locale = Locale(identifier: "zh_CN")
        chineseFormatter.timeZone = .current

        let englishFormatter = DateFormatter()
        englishFormatter.locale = Locale(identifier: "en_US_POSIX")
        englishFormatter.timeZone = .current

        for format in ["yyyy年M月d日", "yyyy-M-d", "yyyy/M/d", "yyyy.M.d"] {
            chineseFormatter.dateFormat = format
            if let date = chineseFormatter.date(from: text) {
                return date
            }
        }

        for format in ["MMM d, yyyy", "MMMM d, yyyy", "M/d/yyyy", "MM/dd/yyyy", "M/d/yy", "MM/dd/yy"] {
            englishFormatter.dateFormat = format
            if let date = englishFormatter.date(from: text) {
                return date
            }
        }

        if let components = monthDayComponents(from: text) {
            return makeDate(month: components.month, day: components.day, referenceDate: referenceDate)
        }

        return nil
    }

    private static func monthDayComponents(from text: String) -> (month: Int, day: Int)? {
        if let rawMonth = firstMatch(in: text, pattern: "(\\d{1,2})月"),
           let rawDay = firstMatch(in: text, pattern: "月(\\d{1,2})日"),
           let month = Int(firstMatch(in: rawMonth, pattern: "\\d{1,2}") ?? ""),
           let day = Int(firstMatch(in: rawDay, pattern: "\\d{1,2}") ?? "") {
            return (month, day)
        }

        let englishNoYearFormats = ["MMM d", "MMMM d", "M/d", "MM/dd"]
        let englishFormatter = DateFormatter()
        englishFormatter.locale = Locale(identifier: "en_US_POSIX")
        englishFormatter.timeZone = .current

        for format in englishNoYearFormats {
            englishFormatter.dateFormat = format
            if let date = englishFormatter.date(from: text) {
                let components = Calendar.current.dateComponents([.month, .day], from: date)
                if let month = components.month, let day = components.day {
                    return (month, day)
                }
            }
        }

        return nil
    }

    private static func makeDate(month: Int, day: Int, referenceDate: Date) -> Date? {
        var components = Calendar.current.dateComponents([.year], from: referenceDate)
        components.month = month
        components.day = day
        guard let date = Calendar.current.date(from: components) else { return nil }

        let referenceDay = Calendar.current.startOfDay(for: referenceDate)
        if date < Calendar.current.date(byAdding: .day, value: -180, to: referenceDay) ?? referenceDay {
            return Calendar.current.date(byAdding: .year, value: 1, to: date)
        }

        return date
    }

    private static func sanitizeOrderID(_ value: String) -> String? {
        let compactValue = value
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "单号", with: "")
            .trimmedFieldValue

        if let orderID = firstMatch(in: compactValue, pattern: "[A-Za-z0-9_-]{6,}") {
            return orderID
        }

        if let digitsOnly = firstMatch(in: compactValue, pattern: "\\d{6,}") {
            return digitsOnly
        }

        return compactValue.isEmpty ? nil : compactValue
    }

    private static func sanitizeGuestName(_ value: String) -> String? {
        if let chineseName = firstMatch(in: value, pattern: "[\\p{Han}]{2,4}") {
            return chineseName
        }

        if let latinName = firstMatch(in: value, pattern: "[A-Za-z]+(?:[ '\\.-][A-Za-z]+){0,2}") {
            return latinName.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return value.trimmedFieldValue.nilIfEmpty
    }

    private static func sanitizePhone(_ value: String) -> String? {
        if let chinaMobile = firstMatch(in: value, pattern: "1[3-9]\\d{9}") {
            return chinaMobile
        }

        if let internationalPhone = firstMatch(in: value, pattern: "\\+?\\d[\\d -]{6,}\\d") {
            return internationalPhone.replacingOccurrences(of: " ", with: "")
        }

        return nil
    }

    private static func firstMatch(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let nsrange = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: nsrange),
              let range = Range(match.range, in: text) else {
            return nil
        }

        return String(text[range])
    }

    private static func matches(in text: String, pattern: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }

        let nsrange = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: nsrange).compactMap { match in
            guard let range = Range(match.range, in: text) else { return nil }
            return String(text[range])
        }
    }

    private static func normalizeLine(_ text: String) -> String {
        text
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmedFieldValue
    }
}

private enum OTABookingImageRecognitionError: LocalizedError {
    case unreadableImage
    case noTextFound
    case noBookingFieldsFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "图片读取失败，请重新拍照或换一张截图。"
        case .noTextFound:
            return "没有识别到文字，请尽量拍清楚订单核心信息后再试。"
        case .noBookingFieldsFound:
            return "识别到了文字，但没有定位到订单号、姓名、日期或价格等关键字段，请手动补充。"
        }
    }
}

private extension String {
    var trimmedFieldValue: String {
        trimmingCharacters(in: CharacterSet(charactersIn: ":：#＃-—_ ").union(.whitespacesAndNewlines))
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
