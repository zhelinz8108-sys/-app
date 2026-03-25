import SwiftUI

/// 夜审页面（管理员专用）
struct NightAuditView: View {
    @ObservedObject private var auditService = NightAuditService.shared
    @State private var auditResult: NightAuditResult?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var approvingRequestID: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 执行夜审按钮
                Button {
                    Task { await runAudit() }
                } label: {
                    HStack {
                        Spacer()
                        if isLoading {
                            ProgressView().tint(.white).padding(.trailing, 6)
                        }
                        Image(systemName: "moon.stars.fill")
                        Text("执行夜审")
                            .fontWeight(.bold)
                        Spacer()
                    }
                    .padding()
                    .background(Color.indigo)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoading)

                if let error = errorMessage {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                if let result = auditResult {
                    auditSummary(result)
                    if !result.overdueReservations.isEmpty {
                        overdueSection(result.overdueReservations)
                    }
                }

                // 延住申请列表
                if !auditService.extendRequests.isEmpty {
                    extendRequestsSection
                }
            }
            .padding()
        }
        .navigationTitle("夜审")
        .task { await runAudit() }
    }

    // MARK: - 夜审汇总

    private func auditSummary(_ result: NightAuditResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("日结汇总", systemImage: "doc.text.fill")
                    .font(.headline)
                Spacer()
                Text(result.auditDate.chineseDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                auditCard("总房数", "\(result.totalRooms)", .blue)
                auditCard("在住", "\(result.occupiedRooms)", .red)
                auditCard("空房", "\(result.vacantRooms)", .green)
                auditCard("已预订", "\(result.reservedRooms)", .purple)
                auditCard("入住率", String(format: "%.0f%%", result.occupancyRate), .indigo)
                auditCard("超期未退", "\(result.overdueReservations.count)", result.overdueReservations.isEmpty ? .gray : .red)
            }

            Divider()

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日入住").font(.caption).foregroundStyle(.secondary)
                    Text("\(result.todayCheckIns) 间").font(.title3).fontWeight(.bold)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日退房").font(.caption).foregroundStyle(.secondary)
                    Text("\(result.todayCheckOuts) 间").font(.title3).fontWeight(.bold)
                }
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("今日营收").font(.caption).foregroundStyle(.secondary)
                    Text("¥\(Int(result.todayRevenue))").font(.title3).fontWeight(.bold).foregroundStyle(.blue)
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func auditCard(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).fontWeight(.bold).foregroundStyle(color)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
    }

    // MARK: - 超期未退

    private func overdueSection(_ reservations: [Reservation]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("超期未退房 (\(reservations.count))", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.red)

            ForEach(reservations) { res in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(res.room?.roomNumber ?? "?")
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(res.guest?.name ?? "未知客人")
                            .font(.subheadline)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("应退: \(res.expectedCheckOut.shortDate)")
                            .font(.caption)
                            .foregroundStyle(.red)
                        let days = Calendar.current.dateComponents([.day], from: res.expectedCheckOut, to: Date()).day ?? 0
                        Text("已超 \(days) 天")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundStyle(.red)
                    }
                }
                .padding(10)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 延住申请

    private var extendRequestsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("延住申请", systemImage: "calendar.badge.clock")
                    .font(.headline)
                if auditService.pendingCount > 0 {
                    Text("\(auditService.pendingCount)待审")
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .foregroundStyle(.white)
                        .clipShape(Capsule())
                }
            }

            ForEach(auditService.extendRequests) { request in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(request.roomNumber)
                            .font(.headline)
                            .fontWeight(.bold)
                        Text(request.guestName)
                            .font(.subheadline)
                        Spacer()
                        Text(request.status.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(statusColor(request.status).opacity(0.15))
                            .foregroundStyle(statusColor(request.status))
                            .clipShape(Capsule())
                    }

                    HStack {
                        Text("原退房 \(request.originalCheckOut.shortDate) → 延至 \(request.requestedCheckOut.shortDate)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("申请人: \(request.requestedBy)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if request.status == .pending {
                        HStack(spacing: 12) {
                            Button {
                                approvingRequestID = request.id
                                Task {
                                    await auditService.approveExtend(requestID: request.id)
                                    approvingRequestID = nil
                                }
                            } label: {
                                HStack {
                                    if approvingRequestID == request.id {
                                        ProgressView()
                                            .tint(.white)
                                            .scaleEffect(0.7)
                                    }
                                    Image(systemName: "checkmark")
                                    Text("批准")
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(approvingRequestID == request.id ? Color.green.opacity(0.5) : Color.green)
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                            }
                            .disabled(approvingRequestID != nil)

                            Button {
                                auditService.rejectExtend(requestID: request.id)
                            } label: {
                                HStack {
                                    Image(systemName: "xmark")
                                    Text("驳回")
                                }
                                .font(.caption)
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(Color.red.opacity(0.15))
                                .foregroundStyle(.red)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }
                .padding(10)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func statusColor(_ status: ExtendStayRequest.ExtendStatus) -> Color {
        switch status {
        case .pending: .orange
        case .approved: .green
        case .rejected: .red
        }
    }

    private func runAudit() async {
        isLoading = true
        errorMessage = nil
        do {
            auditResult = try await auditService.performAudit()
        } catch {
            errorMessage = "夜审执行失败: \(ErrorHelper.userMessage(error))"
        }
        isLoading = false
    }
}
