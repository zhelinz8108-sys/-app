import SwiftUI

@main
struct HotelFrontDeskApp: App {
    // 初始化备份服务（启动自动备份）
    @StateObject private var backupService = BackupService.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
