import SwiftUI

struct CheckInView: View {
    @ObservedObject var roomListViewModel: RoomListViewModel
    @StateObject private var viewModel = CheckInViewModel()
    @Environment(\.dismiss) private var dismiss
    @State private var showReceiptCamera = false

    var body: some View {
        NavigationStack {
            Form {
                // 客人信息
                GuestFormView(
                    name: $viewModel.guestName,
                    idType: $viewModel.idType,
                    idNumber: $viewModel.idNumber,
                    phone: $viewModel.phone,
                    email: $viewModel.guestEmail,
                    notes: $viewModel.guestNotes,
                    numberOfGuests: $viewModel.numberOfGuests
                )

                // 选择房间
                RoomPickerView(
                    vacantRooms: roomListViewModel.vacantRooms,
                    selectedRoom: $viewModel.selectedRoom,
                    onSelectRoom: { room in await viewModel.selectRoom(room) }
                )

                // 入住类型
                Section {
                    Toggle(isOn: $viewModel.isHourlyRoom) {
                        HStack {
                            Image(systemName: viewModel.isHourlyRoom ? "clock.fill" : "moon.fill")
                                .foregroundStyle(viewModel.isHourlyRoom ? .orange : .blue)
                            Text(viewModel.isHourlyRoom ? "钟点房" : "全日房")
                        }
                    }
                    .tint(.orange)

                    if viewModel.isHourlyRoom {
                        // 时长选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("入住时长")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 10) {
                                ForEach(CheckInViewModel.hourlyOptions, id: \.self) { hours in
                                    Button {
                                        viewModel.hourlyDuration = hours
                                    } label: {
                                        Text("\(hours)小时")
                                            .font(.subheadline)
                                            .fontWeight(viewModel.hourlyDuration == hours ? .bold : .regular)
                                            .padding(.horizontal, 14)
                                            .padding(.vertical, 8)
                                            .background(viewModel.hourlyDuration == hours ? Color.orange : Color(.tertiarySystemFill))
                                            .foregroundStyle(viewModel.hourlyDuration == hours ? .white : .primary)
                                            .clipShape(Capsule())
                                    }
                                }
                            }
                        }

                        // 显示预计退房时间
                        HStack {
                            Text("预计退房")
                            Spacer()
                            Text(viewModel.hourlyCheckOut.chineseDateTime)
                                .foregroundStyle(.orange)
                                .fontWeight(.medium)
                        }

                        // 钟点房参考价
                        if let room = viewModel.selectedRoom {
                            HStack {
                                Text("参考价")
                                Spacer()
                                Text("¥\(Int(room.pricePerNight * 0.5))（房价半价）")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("入住类型")
                }

                // 入住信息
                Section("入住信息") {
                    if viewModel.isHourlyRoom {
                        DatePicker("入住时间", selection: $viewModel.checkInDate, displayedComponents: [.date, .hourAndMinute])
                    } else {
                        DatePicker("入住日期", selection: $viewModel.checkInDate, displayedComponents: .date)
                        DatePicker("预计退房", selection: $viewModel.expectedCheckOut, in: viewModel.checkInDate..., displayedComponents: .date)
                    }

                    // 动态价格明细（仅全日房）
                    if !viewModel.isHourlyRoom, let room = viewModel.selectedRoom {
                        let pricing = PricingService.shared
                        let breakdown = pricing.priceBreakdown(
                            room: room,
                            checkIn: viewModel.checkInDate,
                            checkOut: viewModel.expectedCheckOut
                        )

                        if !breakdown.isEmpty {
                            // 统计各类价格的晚数
                            let weekdayNights = breakdown.filter { $0.priceType == .weekday }
                            let weekendNights = breakdown.filter { $0.priceType == .weekend }
                            let specialNights = breakdown.filter { $0.priceType == .special }
                            let total = breakdown.reduce(0) { $0 + $1.price }

                            VStack(alignment: .leading, spacing: 6) {
                                if !weekdayNights.isEmpty {
                                    HStack {
                                        Text("平日")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1))
                                            .clipShape(Capsule())
                                        Spacer()
                                        Text("\(weekdayNights.count)晚 × ¥\(Int(weekdayNights.first?.price ?? 0)) = ¥\(Int(weekdayNights.reduce(0) { $0 + $1.price }))")
                                            .font(.subheadline)
                                    }
                                }
                                if !weekendNights.isEmpty {
                                    HStack {
                                        Text("周末")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.orange.opacity(0.1))
                                            .clipShape(Capsule())
                                        Spacer()
                                        Text("\(weekendNights.count)晚 × ¥\(Int(weekendNights.first?.price ?? 0)) = ¥\(Int(weekendNights.reduce(0) { $0 + $1.price }))")
                                            .font(.subheadline)
                                    }
                                }
                                if !specialNights.isEmpty {
                                    HStack {
                                        Text("特价")
                                            .font(.caption)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.purple.opacity(0.1))
                                            .clipShape(Capsule())
                                        Spacer()
                                        Text("\(specialNights.count)晚 = ¥\(Int(specialNights.reduce(0) { $0 + $1.price }))")
                                            .font(.subheadline)
                                    }
                                }
                                Divider()
                                HStack {
                                    Text("预计房费")
                                        .fontWeight(.medium)
                                    Spacer()
                                    Text("¥\(Int(total))（\(breakdown.count)晚）")
                                        .fontWeight(.bold)
                                        .foregroundStyle(.blue)
                                }
                            }
                        }
                    }

                    // 手动覆盖价格
                    HStack {
                        Text("手动改价 ¥")
                        TextField("留空=使用动态价", text: $viewModel.roomPrice)
                            .keyboardType(.numberPad)
                    }

                    if viewModel.roomPriceValue > 0 {
                        let nights = max(viewModel.checkInDate.daysUntil(viewModel.expectedCheckOut), 1)
                        let total = Double(nights) * viewModel.roomPriceValue
                        HStack {
                            Text("手动房费")
                            Spacer()
                            Text("¥\(Int(total))（\(nights)晚 × ¥\(Int(viewModel.roomPriceValue))）")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // 押金
                Section("押金") {
                    HStack {
                        Text("¥")
                        TextField("押金金额", text: $viewModel.depositAmount)
                            .keyboardType(.numberPad)
                    }

                    if viewModel.depositValue > 0 {
                        // POS小票拍照
                        HStack(spacing: 10) {
                            if let image = viewModel.receiptImage {
                                Image(uiImage: image)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 60, height: 40)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text("小票已拍")
                                    .font(.caption)
                                    .foregroundStyle(.green)
                                Spacer()
                                Button("重拍") { showReceiptCamera = true }
                                    .font(.caption)
                            } else {
                                Button {
                                    showReceiptCamera = true
                                } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: "camera.fill")
                                        Text("拍POS小票")
                                    }
                                    .font(.caption)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 7)
                                    .background(Color.blue.opacity(0.1))
                                    .foregroundStyle(.blue)
                                    .clipShape(Capsule())
                                }
                                Text("拍照留存，退房时可查看")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // 支付方式选择
                        VStack(alignment: .leading, spacing: 8) {
                            Text("支付方式")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(PaymentMethod.allCases) { method in
                                        Button {
                                            viewModel.depositPaymentMethod = method
                                        } label: {
                                            HStack(spacing: 4) {
                                                Image(systemName: method.icon)
                                                    .font(.caption)
                                                Text(method.rawValue)
                                                    .font(.subheadline)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 7)
                                            .background(viewModel.depositPaymentMethod == method ? Color.blue : Color(.tertiarySystemFill))
                                            .foregroundStyle(viewModel.depositPaymentMethod == method ? .white : .primary)
                                            .clipShape(Capsule())
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // 提交
                Section {
                    Button {
                        viewModel.isSubmitting = true // 立即禁用防双击
                        Task {
                            await viewModel.performCheckIn()
                            if viewModel.checkInSuccess {
                                await roomListViewModel.loadRooms()
                                dismiss()
                            }
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if viewModel.isSubmitting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text("确认入住")
                                .fontWeight(.bold)
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                    .disabled(!viewModel.isFormValid || viewModel.isSubmitting)
                }

                // 验证提示
                if !viewModel.validationErrors.isEmpty && !viewModel.guestName.isEmpty {
                    Section {
                        ForEach(viewModel.validationErrors, id: \.self) { err in
                            Label(err, systemImage: "exclamationmark.circle")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                // 错误提示
                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("办理入住")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        viewModel.reset() // 释放房间锁
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showReceiptCamera) {
                ImagePickerView(sourceType: .camera) { image in
                    viewModel.receiptImage = image
                }
            }
        }
    }
}
