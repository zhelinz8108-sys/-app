import UIKit

/// 押金小票照片存储服务
enum ReceiptImageService {
    private static var baseDir: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("HotelLocalData/receipts")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 保存小票照片，返回是否成功
    static func save(depositID: String, image: UIImage) -> Bool {
        guard let data = image.jpegData(compressionQuality: 0.7) else { return false }
        let url = baseDir.appendingPathComponent("\(depositID).jpg")
        do {
            try data.write(to: url)
            return true
        } catch {
            print("保存小票照片失败: \(error)")
            return false
        }
    }

    /// 读取小票照片
    static func load(depositID: String) -> UIImage? {
        let url = baseDir.appendingPathComponent("\(depositID).jpg")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }

    /// 是否有小票照片
    static func exists(depositID: String) -> Bool {
        let url = baseDir.appendingPathComponent("\(depositID).jpg")
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// 删除小票照片
    static func delete(depositID: String) {
        let url = baseDir.appendingPathComponent("\(depositID).jpg")
        try? FileManager.default.removeItem(at: url)
    }
}
