import Foundation
import UIKit

// MARK: - PaddleOCR API 响应模型

struct OCRIDCardResult: Codable {
    let name: String
    let idNumber: String
    let gender: String
    let ethnicity: String
    let birthDate: String
    let address: String
    let rawTexts: [String]
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case name
        case idNumber = "id_number"
        case gender
        case ethnicity
        case birthDate = "birth_date"
        case address
        case rawTexts = "raw_texts"
        case confidence
    }
}

struct OCRPassportResult: Codable {
    let name: String
    let passportNumber: String
    let nationality: String
    let birthDate: String
    let gender: String
    let rawTexts: [String]
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case name
        case passportNumber = "passport_number"
        case nationality
        case birthDate = "birth_date"
        case gender
        case rawTexts = "raw_texts"
        case confidence
    }
}

struct OCRResponse: Codable {
    let success: Bool
    let docType: String
    let idCard: OCRIDCardResult?
    let passport: OCRPassportResult?
    let error: String

    enum CodingKeys: String, CodingKey {
        case success
        case docType = "doc_type"
        case idCard = "id_card"
        case passport
        case error
    }
}

// MARK: - 扫描结果（扩展版，包含更多字段）

struct IDCardScanResultExtended {
    var name: String
    var idNumber: String
    var gender: String
    var ethnicity: String
    var birthDate: String
    var address: String
    var docType: String  // "id_card" | "passport"
    var confidence: Double

    /// 转换为基础扫描结果（兼容现有代码）
    var basic: IDCardScanResult {
        IDCardScanResult(name: name, idNumber: idNumber)
    }
}

// MARK: - PaddleOCR 服务

actor PaddleOCRService {
    static let shared = PaddleOCRService()

    /// OCR 服务地址（可在设置中配置）
    private var serverURL: String {
        UserDefaults.standard.string(forKey: "ocrServerURL") ?? "http://localhost:8089"
    }

    /// 检查 OCR 服务是否可用
    func isAvailable() async -> Bool {
        guard let url = URL(string: "\(serverURL)/health") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    /// 发送图片到 PaddleOCR 服务识别
    func recognize(image: UIImage) async throws -> IDCardScanResultExtended {
        guard let url = URL(string: "\(serverURL)/ocr/id-card") else {
            throw OCRError.invalidURL
        }

        // 压缩图片为 JPEG
        guard let imageData = image.jpegData(compressionQuality: 0.85) else {
            throw OCRError.imageConversionFailed
        }

        // 构建 multipart form data
        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"id_card.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OCRError.serverError
        }

        let ocrResponse = try JSONDecoder().decode(OCRResponse.self, from: data)

        guard ocrResponse.success else {
            throw OCRError.recognitionFailed(ocrResponse.error)
        }

        if let idCard = ocrResponse.idCard {
            return IDCardScanResultExtended(
                name: idCard.name,
                idNumber: idCard.idNumber,
                gender: idCard.gender,
                ethnicity: idCard.ethnicity,
                birthDate: idCard.birthDate,
                address: idCard.address,
                docType: "id_card",
                confidence: idCard.confidence
            )
        } else if let passport = ocrResponse.passport {
            return IDCardScanResultExtended(
                name: passport.name,
                idNumber: passport.passportNumber,
                gender: passport.gender,
                ethnicity: "",
                birthDate: passport.birthDate,
                address: "",
                docType: "passport",
                confidence: passport.confidence
            )
        } else {
            throw OCRError.recognitionFailed("未识别到有效证件信息")
        }
    }
}

// MARK: - OCR 错误

enum OCRError: LocalizedError {
    case invalidURL
    case imageConversionFailed
    case serverError
    case recognitionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "OCR服务地址无效"
        case .imageConversionFailed: return "图片处理失败"
        case .serverError: return "OCR服务连接失败"
        case .recognitionFailed(let msg): return msg
        }
    }
}
