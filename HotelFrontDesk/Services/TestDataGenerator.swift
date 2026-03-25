import Foundation

/// 生成测试数据：100个房间 + 200个客人 + 2个月入住历史
@MainActor
enum TestDataGenerator {

    struct Result {
        let roomCount: Int
        let guestCount: Int
        let historyCount: Int
        let occupiedCount: Int
    }

    static func generate() async throws -> Result {
        let service = CloudKitService.shared

        // ── 姓名库 ──
        let surnames = ["张","王","李","赵","刘","陈","杨","黄","周","吴","徐","孙","马","朱","胡","郭","林","何","高","罗",
                        "郑","梁","谢","宋","唐","许","邓","韩","冯","曹","彭","曾","萧","田","董","潘","袁","蔡","蒋","余",
                        "于","杜","叶","程","苏","魏","吕","丁","任","沈","姚","卢","姜","崔","钟","谭","陆","汪","范","廖"]
        let maleNames = ["伟","强","磊","军","勇","杰","涛","明","超","华","志","建","国","斌","辉","波","鑫","鹏","飞","龙"]
        let femaleNames = ["芳","娜","敏","静","丽","婷","秀","玲","琳","雪","燕","霞","慧","倩","颖","蕾","佳","莉","萍","艳"]

        // ── 朝向/户型/价格配置 ──
        let allOrientations: [RoomOrientation] = [.south, .north, .east, .west, .southEast, .southWest]
        let roomConfigs: [(type: RoomType, basePrice: Double, weekendMult: Double, baseCost: Double, weight: Int)] = [
            (.king,  268, 1.3, 1500, 45),
            (.twin,  238, 1.25, 1200, 35),
            (.suite, 528, 1.35, 2500, 20),
        ]

        func weightedRandomType() -> (RoomType, Double, Double, Double) {
            let roll = Int.random(in: 1...100)
            var cumulative = 0
            for c in roomConfigs {
                cumulative += c.weight
                if roll <= cumulative { return (c.type, c.basePrice, c.basePrice * c.weekendMult, c.baseCost) }
            }
            return (roomConfigs[0].type, roomConfigs[0].basePrice, roomConfigs[0].basePrice * roomConfigs[0].weekendMult, roomConfigs[0].baseCost)
        }

        // ═══════════════════════════════════════
        // 启用批量模式（跳过每次写磁盘，最后统一写）
        LocalStorageService.shared.isBatchMode = true

        // 1. 生成 100 个房间（10层 × 10间）
        // ═══════════════════════════════════════
        var createdRooms: [Room] = []
        for floor in 1...10 {
            for seq in 1...10 {
                let roomNumber = "\(floor)\(String(format: "%02d", seq))"
                let (roomType, basePrice, baseWeekend, baseCost) = weightedRandomType()
                let floorBonus = 1.0 + Double(floor - 1) * 0.03
                let price = (basePrice * floorBonus).rounded()
                let wkPrice = (baseWeekend * floorBonus).rounded()
                let cost = (baseCost * Double.random(in: 0.9...1.1)).rounded()
                let orient = allOrientations.randomElement()!

                var notes: String? = nil
                if Int.random(in: 1...10) == 1 {
                    let noteOptions = ["有窗户","靠电梯","角落房间","有阳台","临街","安静"]
                    notes = noteOptions.randomElement()
                }

                let room = Room(
                    id: "room-\(roomNumber)",
                    roomNumber: roomNumber,
                    floor: floor,
                    roomType: roomType,
                    orientation: orient,
                    status: .vacant,
                    pricePerNight: price,
                    weekendPrice: wkPrice,
                    monthlyCost: cost,
                    notes: notes
                )
                try await service.saveRoom(room)
                createdRooms.append(room)
            }
        }

        // ═══════════════════════════════════════
        // 2. 生成 3000 个客人
        // ═══════════════════════════════════════
        var guestIDs: [String] = []
        for i in 0..<3000 {
            let (guest, guestID): (Guest, String) = autoreleasepool {
                let guestID = UUID().uuidString
                let surname = surnames[i % surnames.count]
                let isFemale = i % 2 == 1
                let givenName = isFemale
                    ? femaleNames[Int.random(in: 0..<femaleNames.count)]
                    : maleNames[Int.random(in: 0..<maleNames.count)]
                let name = surname + givenName

                let prefixes = ["138","139","150","151","186","188","137","159","135","136","158","187","152","182","185","176","178"]
                let phone = prefixes.randomElement()! + String(format: "%08d", Int.random(in: 0...99999999))

                let areaCodes = ["110101","310115","330106","440305","320106","510107","420106","350102","610102","230103"]
                let year = Int.random(in: 1970...2005)
                let month = Int.random(in: 1...12)
                let day = Int.random(in: 1...28)
                let seq = String(format: "%03d", Int.random(in: 1...999))
                let check = String(Int.random(in: 0...9))
                let idNumber = "\(areaCodes.randomElement()!)\(year)\(String(format: "%02d%02d", month, day))\(seq)\(check)"

                let guest = Guest(
                    id: guestID,
                    name: name,
                    idType: i % 20 == 0 ? .passport : .idCard,
                    idNumber: idNumber,
                    phone: phone
                )
                return (guest, guestID)
            }
            guestIDs.append(guestID)
            try await service.saveGuest(guest)
        }

        // ═══════════════════════════════════════
        // 3. 模拟过去 6 个月的入住记录（真实入住率 ~65%）
        // ═══════════════════════════════════════
        var historyCount = 0
        let cal = Calendar.current
        let today = Date()

        for room in createdRooms {
            var dayOffset = -180 // 6个月

            while dayOffset < -1 {
                // 35% 概率空房跳过（模拟真实空置）
                if Int.random(in: 1...100) <= 35 {
                    dayOffset += Int.random(in: 1...3)
                    continue
                }

                let gap = Int.random(in: 0...2)
                dayOffset += gap
                if dayOffset >= -1 { break }

                let nights = Int.random(in: 1...5)
                let checkInDay = dayOffset
                let checkOutDay = min(dayOffset + nights, -1)
                let actualNights = checkOutDay - checkInDay
                if actualNights <= 0 { dayOffset += 1; continue }

                let checkIn = cal.date(byAdding: .day, value: checkInDay, to: today)!
                let checkOut = cal.date(byAdding: .day, value: checkOutDay, to: today)!
                dayOffset = checkOutDay

                // autoreleasepool to reduce peak memory from object creation
                let (reservation, deposit, refund) = autoreleasepool { () -> (Reservation, DepositRecord, DepositRecord) in
                    let guestID = guestIDs.randomElement()!
                    let rate = (room.pricePerNight * Double.random(in: 0.85...1.15)).rounded()

                    let reservation = Reservation(
                        id: UUID().uuidString,
                        guestID: guestID,
                        roomID: room.id,
                        checkInDate: checkIn,
                        expectedCheckOut: checkOut,
                        actualCheckOut: checkOut,
                        isActive: false,
                        numberOfGuests: Int.random(in: 1...3),
                        dailyRate: rate
                    )

                    let depositAmount = Double(Int(rate) / 100 * 100 + 200)
                    let methods: [PaymentMethod] = [.cash, .wechat, .alipay, .bankCard, .pos]
                    let method = methods.randomElement()!
                    let deposit = DepositRecord(
                        id: UUID().uuidString,
                        reservationID: reservation.id,
                        type: .collect,
                        amount: depositAmount,
                        paymentMethod: method,
                        timestamp: checkIn
                    )
                    let refund = DepositRecord(
                        id: UUID().uuidString,
                        reservationID: reservation.id,
                        type: .refund,
                        amount: depositAmount,
                        paymentMethod: method,
                        timestamp: checkOut
                    )
                    return (reservation, deposit, refund)
                }

                try await service.saveReservation(reservation)
                try await service.saveDepositRecord(deposit)
                try await service.saveDepositRecord(refund)
                historyCount += 1
            }
        }

        // ═══════════════════════════════════════
        // 4. 当前入住：随机 30 间设为「已住」
        // ═══════════════════════════════════════
        let occupiedCount = 30
        let shuffledRooms = createdRooms.shuffled()

        for (i, room) in shuffledRooms.prefix(occupiedCount).enumerated() {
            let guestID = guestIDs[i % guestIDs.count]
            let daysAgo = Int.random(in: 0...3)
            let stayLength = Int.random(in: 1...5)
            let checkIn = cal.date(byAdding: .day, value: -daysAgo, to: today)!
            let expectedOut = cal.date(byAdding: .day, value: stayLength - daysAgo, to: today)!

            let reservation = Reservation(
                id: UUID().uuidString,
                guestID: guestID,
                roomID: room.id,
                checkInDate: checkIn,
                expectedCheckOut: expectedOut,
                isActive: true,
                numberOfGuests: Int.random(in: 1...2),
                dailyRate: room.pricePerNight
            )
            try await service.saveReservation(reservation)

            let deposit = DepositRecord(
                id: UUID().uuidString,
                reservationID: reservation.id,
                type: .collect,
                amount: Double(Int(room.pricePerNight) / 100 * 100 + 200),
                paymentMethod: [PaymentMethod.cash, .wechat, .alipay, .pos].randomElement()!,
                timestamp: checkIn
            )
            try await service.saveDepositRecord(deposit)
            try await service.updateRoomStatus(roomID: room.id, status: .occupied)
        }

        // 5 间脏房，3 间维修中，3 间已预订
        for room in shuffledRooms.dropFirst(occupiedCount).prefix(5) {
            try await service.updateRoomStatus(roomID: room.id, status: .cleaning)
        }
        for room in shuffledRooms.dropFirst(occupiedCount + 5).prefix(3) {
            try await service.updateRoomStatus(roomID: room.id, status: .maintenance)
        }
        for room in shuffledRooms.dropFirst(occupiedCount + 8).prefix(3) {
            try await service.updateRoomStatus(roomID: room.id, status: .reserved)
        }

        // ═══════════════════════════════════════
        // 6. 模拟 OTA 预订（含取消、未到店）
        // ═══════════════════════════════════════
        let otaService = OTABookingService.shared
        let platforms: [OTAPlatform] = [.meituan, .fliggy, .ctrip, .booking, .direct]
        let roomTypes: [RoomType] = [.king, .twin, .suite]

        for i in 0..<60 {
            let daysFromNow = Int.random(in: -30...14)
            let bookingDate = cal.date(byAdding: .day, value: daysFromNow, to: today)!
            let nights = Int.random(in: 1...4)
            let platform = platforms.randomElement()!
            let price = Double([238, 258, 268, 298, 328, 388, 528].randomElement()!)
            let guestName = [
                "王伟","李娜","张强","刘敏","陈杰","杨静","赵涛","黄丽",
                "周超","吴华","徐芳","孙明","马志","朱婷","胡磊","郭燕"
            ].randomElement()!

            let status: BookingStatus
            let roll = Int.random(in: 1...10)
            if daysFromNow < -3 {
                // 过去的预订：已入住、已取消、未到店
                if roll <= 7 { status = .checkedIn }
                else if roll <= 9 { status = .cancelled }
                else { status = .noShow }
            } else {
                // 未来/今天的预订：已确认、少量取消
                if roll <= 8 { status = .confirmed }
                else { status = .cancelled }
            }

            let booking = OTABooking(
                platform: platform,
                platformOrderID: "OTA\(String(format: "%06d", i + 1))",
                guestName: guestName,
                guestPhone: "1\(Int.random(in: 30...99))\(String(format: "%08d", Int.random(in: 0...99999999)))",
                roomType: roomTypes.randomElement()!,
                checkInDate: bookingDate,
                nights: nights,
                price: price,
                status: status,
                createdBy: "系统"
            )
            otaService.add(booking)
        }

        // ═══════════════════════════════════════
        // 7. 模拟延住申请（含批准/驳回）
        // ═══════════════════════════════════════
        let auditService = NightAuditService.shared
        let activeReservations = LocalStorageService.shared.fetchActiveReservations()
        for res in activeReservations.prefix(5) {
            guard let newCheckOut = cal.date(byAdding: .day, value: Int.random(in: 1...3), to: res.expectedCheckOut) else { continue }
            let request = ExtendStayRequest(
                id: UUID().uuidString,
                reservationID: res.id,
                roomID: res.roomID,
                roomNumber: createdRooms.first { $0.id == res.roomID }?.roomNumber ?? "?",
                guestName: res.guest?.name ?? "未知",
                originalCheckOut: res.expectedCheckOut,
                requestedCheckOut: newCheckOut,
                requestedBy: ["张前台", "李前台", "王前台"].randomElement()!,
                requestedAt: Date(),
                status: [.pending, .pending, .approved, .rejected].randomElement()!
            )
            auditService.extendRequests.append(request)
        }

        // ═══════════════════════════════════════
        // 8. 模拟操作日志
        // ═══════════════════════════════════════
        let logService = OperationLogService.shared
        let operators = ["张前台", "李前台", "王前台", "管理员"]

        // 换房记录
        for i in 0..<8 {
            let fromRoom = createdRooms.randomElement()!
            let toRoom = createdRooms.filter { $0.id != fromRoom.id }.randomElement()!
            let gName = guestIDs.prefix(200).randomElement().flatMap { LocalStorageService.shared.fetchGuest(id: $0)?.name } ?? "客人\(i)"
            let entry = OperationLog(
                type: .roomStatusChange,
                summary: "\(gName) 换房 \(fromRoom.roomNumber) → \(toRoom.roomNumber)",
                detail: "原房: \(fromRoom.roomNumber)(\(fromRoom.roomType.rawValue)) → 新房: \(toRoom.roomNumber)(\(toRoom.roomType.rawValue)) | 原因: \(["客人嫌吵","空调故障","升级房型","客人要求换朝向"].randomElement()!)",
                roomNumber: toRoom.roomNumber,
                staffName: operators.randomElement()!,
                staffRole: "前台员工"
            )
            logService.log(type: entry.type, summary: entry.summary, detail: entry.detail, roomNumber: entry.roomNumber)
        }

        // 批量写入磁盘
        LocalStorageService.shared.flushAll()

        return Result(
            roomCount: createdRooms.count,
            guestCount: 3000,
            historyCount: historyCount,
            occupiedCount: occupiedCount
        )
    }
}
