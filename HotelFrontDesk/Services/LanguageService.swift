import SwiftUI

/// 应用内语言实时切换服务
@MainActor
final class LanguageService: ObservableObject {
    static let shared = LanguageService()

    enum AppLanguage: String, CaseIterable, Identifiable {
        case system = "system"
        case zhHans = "zh-Hans"
        case en = "en"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .system: "跟随系统 / System"
            case .zhHans: "中文"
            case .en: "English"
            }
        }
    }

    @Published var currentLanguage: AppLanguage {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "appLanguage")
            applyLanguage()
        }
    }

    /// 当前使用的 Bundle（用于 String(localized:) 替代方案）
    @Published var bundle: Bundle = .main

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage") ?? "system"
        self.currentLanguage = AppLanguage(rawValue: saved) ?? .system
        applyLanguage()
    }

    private func applyLanguage() {
        let langCode: String?
        switch currentLanguage {
        case .system: langCode = nil
        case .zhHans: langCode = "zh-Hans"
        case .en: langCode = "en"
        }

        if let code = langCode,
           let path = Bundle.main.path(forResource: code, ofType: "lproj"),
           let langBundle = Bundle(path: path) {
            bundle = langBundle
        } else {
            bundle = .main
        }

        // 同时设置 AppleLanguages 让系统控件也跟着变（下次启动生效）
        if let code = langCode {
            UserDefaults.standard.set([code], forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        }
    }

    /// 获取本地化字符串（nonisolated 安全访问 bundle）
    nonisolated func localized(_ key: String) -> String {
        // bundle is set on MainActor but Bundle is thread-safe for reads
        let b = MainActor.assumeIsolated { bundle }
        return b.localizedString(forKey: key, value: nil, table: nil)
    }
}

/// 便捷函数：用当前语言获取本地化字符串
func L(_ key: String) -> String {
    MainActor.assumeIsolated {
        LanguageService.shared.localized(key)
    }
}
