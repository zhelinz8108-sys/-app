import SwiftUI

struct ContentView: View {
    @StateObject private var staffService = StaffService.shared
    @StateObject private var cloudKit = CloudKitService.shared
    @ObservedObject private var lang = LanguageService.shared
    @StateObject private var overdueMonitor = OverdueCheckoutMonitor.shared
    @State private var showRecoveryGuide = false

    var body: some View {
        if staffService.isLoggedIn {
            if staffService.requiresMandatoryPasswordChange {
                MandatoryPasswordChangeView()
            } else {
                mainTabView
                    .onAppear { overdueMonitor.start() }
                    .onDisappear { overdueMonitor.stop() }
                    .onChange(of: cloudKit.dataProtectionIssue) { _, newValue in
                        if newValue != nil {
                            showRecoveryGuide = true
                        }
                    }
                    .alert("超期未退房提醒", isPresented: $overdueMonitor.showAlert) {
                        Button("知道了") {
                            overdueMonitor.dismissAlert()
                        }
                    } message: {
                        Text(overdueMonitor.alertMessage)
                    }
                    .sheet(isPresented: $showRecoveryGuide) {
                        NavigationStack {
                            BackupSettingsView()
                        }
                    }
            }
        } else {
            StaffLoginView(staffService: staffService)
        }
    }

    private var mainTabView: some View {
        VStack(spacing: 0) {
            if let issue = cloudKit.dataProtectionIssue {
                Button {
                    showRecoveryGuide = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "shield.lefthalf.filled.badge.exclamationmark")
                            .font(.caption)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("数据保护异常")
                                .font(.caption)
                                .fontWeight(.semibold)
                            Text(issue)
                                .font(.caption2)
                                .lineLimit(2)
                        }
                        Spacer()
                        Text("恢复指引")
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            // 网络状态横幅 — dark navy luxury style
            if cloudKit.isLocalMode {
                HStack(spacing: 6) {
                    Image(systemName: "wifi.slash")
                        .font(.caption2)
                    Text(L("network.localMode"))
                        .font(.caption2)
                        .fontWeight(.medium)
                    Spacer()
                    if cloudKit.isReadOnlyMode {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                        Text(L("network.writeLocked"))
                            .font(.caption2)
                    } else {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                        Text(L("network.retrying"))
                            .font(.caption2)
                    }
                }
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.appPrimary)
            }

            TabView {
                DashboardView()
                    .tabItem {
                        Label(L("tab.overview"), systemImage: "house.fill")
                    }

                RoomGridView()
                    .tabItem {
                        Label(L("tab.rooms"), systemImage: "square.grid.3x3.fill")
                    }

                OTABookingListView()
                    .tabItem {
                        Label("预订", systemImage: "calendar.badge.plus")
                    }

                if staffService.isManager {
                    AnalyticsView()
                        .tabItem {
                            Label(L("tab.analytics"), systemImage: "chart.bar.fill")
                        }

                    OperationLogView()
                        .tabItem {
                            Label(L("tab.logs"), systemImage: "doc.text.magnifyingglass")
                        }
                }

                RoomSetupView()
                    .tabItem {
                        Label(L("tab.settings"), systemImage: "gearshape.fill")
                    }
            }
            .tint(.appAccent)
        }
    }
}

#Preview {
    ContentView()
}
