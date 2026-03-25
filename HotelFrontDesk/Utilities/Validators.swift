import Foundation

/// 数据验证工具
enum Validators {

    /// 验证中国手机号（1开头，11位数字）
    static func isValidPhone(_ phone: String) -> Bool {
        let trimmed = phone.trimmingCharacters(in: .whitespaces)
        guard trimmed.count == 11 else { return false }
        let regex = "^1[3-9]\\d{9}$"
        return trimmed.range(of: regex, options: .regularExpression) != nil
    }

    /// 验证身份证号（18位，最后一位可以是X）
    static func isValidIDCard(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count == 18 else { return false }
        let regex = "^\\d{17}[\\dX]$"
        guard trimmed.range(of: regex, options: .regularExpression) != nil else { return false }
        // 校验位验证
        let weights = [7, 9, 10, 5, 8, 4, 2, 1, 6, 3, 7, 9, 10, 5, 8, 4, 2]
        let checkChars: [Character] = ["1","0","X","9","8","7","6","5","4","3","2"]
        let chars = Array(trimmed)
        var sum = 0
        for i in 0..<17 {
            guard let digit = chars[i].wholeNumberValue else { return false }
            sum += digit * weights[i]
        }
        return chars[17] == checkChars[sum % 11]
    }

    /// 验证护照号（字母开头，6-9位字母数字）
    static func isValidPassport(_ id: String) -> Bool {
        let trimmed = id.trimmingCharacters(in: .whitespaces).uppercased()
        guard trimmed.count >= 6 && trimmed.count <= 9 else { return false }
        let regex = "^[A-Z][A-Z0-9]{5,8}$"
        return trimmed.range(of: regex, options: .regularExpression) != nil
    }

    /// 验证房价范围（0-99999）
    static func isValidPrice(_ price: Double) -> Bool {
        price >= 0 && price <= 99999
    }

    /// 格式化手机号显示（138****8000）
    static func maskedPhone(_ phone: String) -> String {
        guard phone.count == 11 else { return phone }
        let start = phone.prefix(3)
        let end = phone.suffix(4)
        return "\(start)****\(end)"
    }

    /// 格式化身份证号显示（3301**********1234）
    static func maskedIDCard(_ id: String) -> String {
        guard id.count == 18 else { return id }
        let start = id.prefix(4)
        let end = id.suffix(4)
        return "\(start)**********\(end)"
    }

    /// 通用敏感信息脱敏
    static func maskedSensitive(
        _ value: String,
        prefixCount: Int = 2,
        suffixCount: Int = 2,
        minimumMaskCount: Int = 4
    ) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        guard trimmed.count > prefixCount + suffixCount else { return trimmed }
        let prefix = trimmed.prefix(prefixCount)
        let suffix = trimmed.suffix(suffixCount)
        let maskCount = max(minimumMaskCount, trimmed.count - prefixCount - suffixCount)
        return "\(prefix)\(String(repeating: "*", count: maskCount))\(suffix)"
    }
}
