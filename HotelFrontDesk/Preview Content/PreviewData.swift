import Foundation

// MARK: - 预览用样本数据
enum PreviewData {

    // MARK: 房间
    static let rooms: [Room] = {
        var list: [Room] = []
        let types: [RoomType] = [.king, .twin, .suite]
        let orientations: [RoomOrientation] = [.south, .north, .east, .west]
        let prices: [RoomType: Double] = [
            .king: 288, .twin: 258, .suite: 588
        ]

        for floor in 1...3 {
            for num in 1...8 {
                let roomNumber = "\(floor)\(String(format: "%02d", num))"
                let roomType = types[(floor - 1 + num) % types.count]
                let orientation = orientations[(floor + num) % orientations.count]
                // 模拟不同状态
                let status: RoomStatus
                switch (floor, num) {
                case (_, 1), (_, 3), (_, 5), (_, 7): status = .vacant
                case (_, 2), (_, 4): status = .occupied
                case (_, 6): status = .cleaning
                case (_, 8): status = .maintenance
                default: status = .vacant
                }

                list.append(Room(
                    id: "room-\(roomNumber)",
                    roomNumber: roomNumber,
                    floor: floor,
                    roomType: roomType,
                    orientation: orientation,
                    status: status,
                    pricePerNight: prices[roomType] ?? 258,
                    weekendPrice: (prices[roomType] ?? 258) * 1.3,
                    monthlyCost: [RoomType.king: 1500, .twin: 1200, .suite: 2500][roomType] ?? 1500,
                    notes: status == .maintenance ? "空调维修中" : nil
                ))
            }
        }
        return list
    }()

    // MARK: 客人
    static let guests: [Guest] = [
        Guest(id: "guest-1", name: "张三", idType: .idCard, idNumber: "330106199001011234", phone: "13800138001"),
        Guest(id: "guest-2", name: "李四", idType: .passport, idNumber: "E12345678", phone: "13900139002"),
    ]

    // MARK: 入住记录
    static let reservations: [Reservation] = [
        Reservation(
            id: "res-1",
            guestID: "guest-1",
            roomID: "room-102",
            checkInDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            expectedCheckOut: Date.tomorrow,
            isActive: true,
            numberOfGuests: 1,
            dailyRate: 258,
            guest: guests[0],
            room: rooms.first { $0.roomNumber == "102" }
        ),
        Reservation(
            id: "res-2",
            guestID: "guest-2",
            roomID: "room-104",
            checkInDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())!,
            expectedCheckOut: Calendar.current.date(byAdding: .day, value: 2, to: Date())!,
            isActive: true,
            numberOfGuests: 2,
            dailyRate: 288,
            guest: guests[1],
            room: rooms.first { $0.roomNumber == "104" }
        ),
    ]

    // MARK: 押金记录
    static let depositRecords: [DepositRecord] = [
        DepositRecord(
            id: "dep-1",
            reservationID: "res-1",
            type: .collect,
            amount: 500,
            paymentMethod: .wechat,
            timestamp: Calendar.current.date(byAdding: .day, value: -2, to: Date())!,
            notes: "POS回单 #20260317001"
        ),
        DepositRecord(
            id: "dep-2",
            reservationID: "res-2",
            type: .collect,
            amount: 800,
            paymentMethod: .cash,
            timestamp: Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        ),
    ]
}
