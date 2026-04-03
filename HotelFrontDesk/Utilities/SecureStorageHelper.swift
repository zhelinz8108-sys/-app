import Foundation

enum SecureStorageHelper {
    private static let protection: FileProtectionType = .completeUntilFirstUserAuthentication

    static func ensureDirectory(
        at url: URL,
        fileManager: FileManager = .default,
        excludeFromBackup: Bool = false
    ) {
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            try fileManager.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
            if excludeFromBackup {
                try setExcludedFromBackup(for: url)
            }
        } catch {
            // Best-effort hardening. Persistence should keep working even if protection flags fail.
        }
    }

    static func write(
        _ data: Data,
        to url: URL,
        options: Data.WritingOptions = [.atomic],
        fileManager: FileManager = .default,
        excludeFromBackup: Bool = false
    ) throws {
        ensureDirectory(at: url.deletingLastPathComponent(), fileManager: fileManager)
        try data.write(to: url, options: options)
        try? fileManager.setAttributes([.protectionKey: protection], ofItemAtPath: url.path)
        if excludeFromBackup {
            try? setExcludedFromBackup(for: url)
        }
    }

    static func setExcludedFromBackup(for url: URL, excluded: Bool = true) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = excluded
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }
}
