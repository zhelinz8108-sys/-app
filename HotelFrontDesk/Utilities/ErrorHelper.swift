import Foundation

/// 将系统错误转换为用户友好的中文描述
enum ErrorHelper {
    static func userMessage(_ error: Error) -> String {
        let desc = error.localizedDescription

        // 网络相关
        if desc.contains("network") || desc.contains("Internet") || desc.contains("offline") {
            return "网络连接失败，请检查网络后重试"
        }
        if desc.contains("timed out") || desc.contains("Timeout") {
            return "操作超时，请重试"
        }

        // CloudKit 相关
        if desc.contains("CKError") || desc.contains("CloudKit") {
            return "iCloud 服务异常，数据已保存到本地"
        }
        if desc.contains("not authenticated") || desc.contains("Account") {
            return "iCloud 账号未登录"
        }

        // 文件相关
        if desc.contains("disk") || desc.contains("space") || desc.contains("storage") {
            return "设备存储空间不足"
        }
        if desc.contains("permission") || desc.contains("denied") {
            return "没有访问权限"
        }

        // 数据相关
        if desc.contains("decode") || desc.contains("corrupt") {
            return "数据格式异常，请联系管理员"
        }

        // 其他：如果是中文就直接返回，否则包一层
        if desc.range(of: "[\u{4e00}-\u{9fff}]", options: .regularExpression) != nil {
            return desc
        }

        return "操作失败，请重试"
    }
}
