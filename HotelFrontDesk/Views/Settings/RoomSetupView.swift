import SwiftUI

struct RoomSetupView: View {
    @State private var rooms: [Room] = []
    @State private var isLoading = false
    @State private var showAddRoom = false
    @State private var editingRoom: Room?
    @State private var resultMessage: String?
    @State private var showResult = false
    @State private var isSeedingHistory = false

    @ObservedObject private var appSettings = AppSettings.shared
    @ObservedObject private var staffService = StaffService.shared
    @ObservedObject private var languageService = LanguageService.shared

    // 新增房间表单
    @State private var newRoomNumber = ""
    @State private var newFloor = ""
    @State private var newRoomType: RoomType = .king
    @State private var newOrientation: RoomOrientation = .south
    @State private var newPrice = "258"
    @State private var newWeekendPrice = "328"
    @State private var newMonthlyCost = "1500"
    @State private var newNotes = ""

    private let service = CloudKitService.shared
    private let logService = OperationLogService.shared

    var body: some View {
        NavigationStack {
            List {
                // MARK: - 当前账号
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: staffService.isManager ? "person.badge.key.fill" : "person.circle.fill")
                            .font(.title2)
                            .foregroundStyle(staffService.isManager ? .orange : .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(staffService.currentName)
                                .fontWeight(.medium)
                            Text(staffService.currentStaff?.role.rawValue ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("退出登录") {
                            staffService.logout()
                        }
                        .foregroundStyle(.red)
                        .font(.callout)
                    }

                    if staffService.isManager {
                        NavigationLink {
                            StaffManageView()
                        } label: {
                            Label("员工管理", systemImage: "person.3.fill")
                        }
                        NavigationLink {
                            SpecialDatePriceView()
                        } label: {
                            Label("特殊日期定价", systemImage: "calendar.badge.clock")
                        }
                    }
                } header: {
                    Text("账号")
                } footer: {
                    Text(staffService.isManager
                         ? "管理员可查看数据分析、操作日志，管理员工和房间"
                         : "前台员工可办理入住/退房、查看房态")
                }

                // MARK: - 备份与恢复
                Section {
                    NavigationLink {
                        BackupSettingsView()
                    } label: {
                        HStack {
                            Label("备份与恢复", systemImage: "icloud.and.arrow.up")
                            Spacer()
                            if let last = BackupService.shared.lastBackupTime {
                                Text(formatBackupTime(last))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("数据安全")
                } footer: {
                    Text("CloudKit 同步 + iCloud Drive 自动备份，双重保险")
                }

                // MARK: - 语言设置
                Section {
                    HStack {
                        Label("语言 / Language", systemImage: "globe")
                        Spacer()
                        Picker("", selection: $languageService.currentLanguage) {
                            ForEach(LanguageService.AppLanguage.allCases) { lang in
                                Text(lang.displayName).tag(lang)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                    if languageService.currentLanguage != .system {
                        Text("切换语言后需要重启 app 生效")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("语言 / Language")
                }

                // MARK: - 已有房间列表
                if rooms.isEmpty && !isLoading {
                    Section {
                        ContentUnavailableView(
                            "还没有房间",
                            systemImage: "bed.double",
                            description: Text(appSettings.isManagerMode
                                ? "点击右上角 + 添加第一个房间"
                                : "请联系管理员添加房间")
                        )
                    }
                } else {
                    // 按楼层分组
                    let floors = Dictionary(grouping: rooms) { $0.floor }.sorted { $0.key < $1.key }

                    ForEach(floors, id: \.key) { floor, floorRooms in
                        Section("\(floor)楼 · \(floorRooms.count)间") {
                            ForEach(floorRooms.sorted { $0.roomNumber < $1.roomNumber }) { room in
                                roomRow(room)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if appSettings.isManagerMode {
                                            Button(role: .destructive) {
                                                Task { await deleteRoom(room) }
                                            } label: {
                                                Label("删除", systemImage: "trash")
                                            }
                                            Button {
                                                startEditing(room)
                                            } label: {
                                                Label("编辑", systemImage: "pencil")
                                            }
                                            .tint(.blue)
                                        }
                                    }
                            }
                        }
                    }
                }

                // MARK: - 测试数据（仅管理员）
                if appSettings.isManagerMode {
                    Section("测试数据") {
                        Button {
                            Task { await seedHistoryData() }
                        } label: {
                            HStack {
                                Spacer()
                                if isSeedingHistory {
                                    ProgressView()
                                        .padding(.trailing, 8)
                                }
                                Label("一键生成测试数据", systemImage: "wand.and.stars")
                                Spacer()
                            }
                            .padding(.vertical, 4)
                        }
                        .disabled(isSeedingHistory)

                        Text("100间房 · 3000客人 · 半年入住 · OTA预订 · 换房 · 延住 · 取消")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                }
            }
            .navigationTitle("房间管理")
            .toolbar {
                if appSettings.isManagerMode {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            resetForm()
                            editingRoom = nil
                            showAddRoom = true
                        } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView("加载中...")
                }
            }
            .task {
                await loadRooms()
            }
            .sheet(isPresented: $showAddRoom) {
                roomFormSheet
            }
            .alert("结果", isPresented: $showResult) {
                Button("确定") {}
            } message: {
                Text(resultMessage ?? "")
            }
        }
    }

    // MARK: - 房间行
    private func roomRow(_ room: Room) -> some View {
        HStack(spacing: 12) {
            // 房号
            Text(room.roomNumber)
                .font(.title3)
                .fontWeight(.bold)
                .frame(width: 50)

            // 信息
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(room.roomType.rawValue)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .clipShape(Capsule())

                    Text(room.orientation.rawValue)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.1))
                        .clipShape(Capsule())
                }

                if let notes = room.notes, !notes.isEmpty {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // 房价
            Text("¥\(Int(room.pricePerNight))")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.blue)

            // 状态
            RoomStatusBadge(status: room.status)
        }
        .padding(.vertical, 4)
    }

    // MARK: - 添加/编辑房间表单
    private var roomFormSheet: some View {
        NavigationStack {
            Form {
                Section("房间信息") {
                    HStack {
                        Text("房号")
                        Spacer()
                        TextField("如 101", text: $newRoomNumber)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    HStack {
                        Text("楼层")
                        Spacer()
                        TextField("如 4", text: $newFloor)
                            .multilineTextAlignment(.trailing)
                            .keyboardType(.numberPad)
                    }

                    Picker("户型", selection: $newRoomType) {
                        ForEach(RoomType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    Picker("朝向", selection: $newOrientation) {
                        ForEach(RoomOrientation.allCases) { orient in
                            Text(orient.rawValue).tag(orient)
                        }
                    }
                }

                Section("价格") {
                    HStack {
                        Text("平日价 ¥")
                        TextField("周一至周四", text: $newPrice)
                            .keyboardType(.numberPad)
                    }
                    HStack {
                        Text("周末价 ¥")
                        TextField("周五周六", text: $newWeekendPrice)
                            .keyboardType(.numberPad)
                    }
                    if appSettings.isManagerMode {
                        HStack {
                            Text("每月成本 ¥")
                            TextField("水电折旧清洁等", text: $newMonthlyCost)
                                .keyboardType(.numberPad)
                        }
                    }
                }

                Section("备注（选填）") {
                    TextField("如：有窗户、靠电梯等", text: $newNotes)
                }
            }
            .navigationTitle(editingRoom != nil ? "编辑房间" : "添加房间")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { showAddRoom = false }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(editingRoom != nil ? "保存" : "添加") {
                        Task { await saveRoom() }
                    }
                    .fontWeight(.bold)
                    .disabled(newRoomNumber.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    // MARK: - 操作方法

    private func loadRooms() async {
        isLoading = true
        do {
            rooms = try await service.fetchAllRooms()
        } catch {
            print("加载房间失败: \(error)")
        }
        isLoading = false
    }

    private func saveRoom() async {
        let trimmedNumber = newRoomNumber.trimmingCharacters(in: .whitespaces)
        guard !trimmedNumber.isEmpty else { return }

        let price = Double(newPrice) ?? 258
        let wkPrice = Double(newWeekendPrice) ?? editingRoom?.weekendPrice ?? 0
        let floorNum = Int(newFloor) ?? 1
        let cost = Double(newMonthlyCost) ?? editingRoom?.monthlyCost ?? 0
        let room = Room(
            id: editingRoom?.id ?? "room-\(trimmedNumber)",
            roomNumber: trimmedNumber,
            floor: floorNum,
            roomType: newRoomType,
            orientation: newOrientation,
            status: editingRoom?.status ?? .vacant,
            pricePerNight: price,
            weekendPrice: wkPrice,
            monthlyCost: cost,
            notes: newNotes.isEmpty ? nil : newNotes
        )

        do {
            let isEditing = editingRoom != nil
            try await service.saveRoom(room)
            if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[idx] = room
            } else {
                rooms.append(room)
            }
            logService.log(
                type: isEditing ? .roomEdit : .roomAdd,
                summary: isEditing ? "编辑房间 \(room.roomNumber)" : "新增房间 \(room.roomNumber)",
                detail: "房号: \(room.roomNumber) | \(room.floor)楼 | \(room.roomType.rawValue) | \(room.orientation.rawValue) | 房价: ¥\(Int(room.pricePerNight))/晚 | 月成本: ¥\(Int(room.monthlyCost))\(room.notes.map { " | 备注: \($0)" } ?? "")",
                roomNumber: room.roomNumber
            )
            showAddRoom = false
        } catch {
            resultMessage = "保存失败: \(ErrorHelper.userMessage(error))"
            showResult = true
        }
    }

    private func deleteRoom(_ room: Room) async {
        do {
            try await service.deleteRoom(id: room.id)
            rooms.removeAll { $0.id == room.id }
            logService.log(
                type: .roomDelete,
                summary: "删除房间 \(room.roomNumber)",
                detail: "房号: \(room.roomNumber) | \(room.floor)楼 | \(room.roomType.rawValue) | 房价: ¥\(Int(room.pricePerNight))/晚",
                roomNumber: room.roomNumber
            )
        } catch {
            resultMessage = "删除失败: \(ErrorHelper.userMessage(error))"
            showResult = true
        }
    }

    private func startEditing(_ room: Room) {
        editingRoom = room
        newRoomNumber = room.roomNumber
        newFloor = String(room.floor)
        newRoomType = room.roomType
        newOrientation = room.orientation
        newPrice = String(Int(room.pricePerNight))
        newWeekendPrice = String(Int(room.weekendPrice))
        newMonthlyCost = String(Int(room.monthlyCost))
        newNotes = room.notes ?? ""
        showAddRoom = true
    }

    private func resetForm() {
        newRoomNumber = ""
        newFloor = ""
        newRoomType = .king
        newOrientation = .south
        newPrice = "258"
        newWeekendPrice = "328"
        newMonthlyCost = "1500"
        newNotes = ""
    }

    private func seedHistoryData() async {
        isSeedingHistory = true
        do {
            let result = try await TestDataGenerator.generate()
            rooms = try await service.fetchAllRooms()
            logService.log(
                type: .testDataGenerate,
                summary: "生成测试数据",
                detail: "\(result.roomCount)间房 | \(result.guestCount)位客人 | \(result.historyCount)条历史 | \(result.occupiedCount)间在住"
            )
            resultMessage = "✅ 已生成 \(result.roomCount)间房 + \(result.guestCount)位客人 + \(result.historyCount)条历史（半年）\n30间在住 · 5间脏房 · 3间维修 · 3间预订 · 60条OTA · 5条延住"
        } catch {
            resultMessage = "生成失败: \(ErrorHelper.userMessage(error))"
        }
        showResult = true
        isSeedingHistory = false
    }
    private func formatBackupTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "M/d HH:mm"
        return f.string(from: date)
    }
}

#Preview {
    RoomSetupView()
}
