import Foundation

// MARK: - 本地 JSON 文件存储（CloudKit 不可用时的备选方案）
@MainActor
final class LocalStorageService {
    static let shared = LocalStorageService()

    private let fileManager = FileManager.default
    private let baseDir: URL

    // 内存缓存
    private var rooms: [Room] = []
    private var guests: [String: Guest] = [:]
    private var reservations: [Reservation] = []
    private var deposits: [DepositRecord] = []

    private init() {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
        baseDir = docs.appendingPathComponent("HotelLocalData")
        SecureStorageHelper.ensureDirectory(at: baseDir, excludeFromBackup: true)
        loadAll()
    }

    // MARK: - Room 操作

    func fetchAllRooms() -> [Room] {
        rooms.sorted { ($0.floor, $0.roomNumber) < ($1.floor, $1.roomNumber) }
    }

    func saveRoom(_ room: Room) {
        upsertRoom(room, markDirty: true)
    }

    func saveRooms(_ newRooms: [Room]) {
        upsertRooms(newRooms, markDirty: true)
    }

    func mirrorRoom(_ room: Room) {
        upsertRoom(room, markDirty: false)
    }

    func mirrorRooms(_ newRooms: [Room]) {
        upsertRooms(newRooms, markDirty: false)
    }

    func mirrorDeleteRoom(id: String) {
        removeRoom(id: id, markDirty: false)
    }

    func replaceRooms(_ newRooms: [Room]) {
        rooms = makeUnique(newRooms, id: \.id)
        persist(type: .rooms, markDirty: false)
    }

    func updateRoomStatus(roomID: String, status: RoomStatus) {
        setRoomStatus(roomID: roomID, status: status, markDirty: true)
    }

    func deleteRoom(id: String) {
        removeRoom(id: id, markDirty: true)
    }

    func deleteAllRooms() {
        rooms.removeAll()
        persist(type: .rooms, markDirty: true)
    }

    /// 清除所有数据（仅用于测试）
    func resetAll() {
        rooms.removeAll()
        guests.removeAll()
        reservations.removeAll()
        deposits.removeAll()
        persistAll(markDirty: true)
    }

    // MARK: - Guest 操作

    func saveGuest(_ guest: Guest) {
        upsertGuest(guest, markDirty: true)
    }

    func fetchGuest(id: String) -> Guest? {
        guests[id]
    }

    func fetchAllGuests() -> [Guest] {
        guests.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func deleteGuest(id: String) {
        removeGuest(id: id, markDirty: true)
    }

    func mirrorGuest(_ guest: Guest) {
        upsertGuest(guest, markDirty: false)
    }

    func mirrorGuests(_ guests: [Guest]) {
        upsertGuests(guests, markDirty: false)
    }

    func mirrorDeleteGuest(id: String) {
        removeGuest(id: id, markDirty: false)
    }

    func replaceGuests(_ newGuests: [Guest]) {
        guests = makeGuestMap(newGuests)
        persist(type: .guests, markDirty: false)
    }

    private func removeGuest(id: String, markDirty: Bool) {
        let reservationIDs = Set(reservations.filter { $0.guestID == id }.map(\.id))
        guests.removeValue(forKey: id)
        reservations.removeAll { $0.guestID == id }
        if !reservationIDs.isEmpty {
            deposits.removeAll { reservationIDs.contains($0.reservationID) }
        }
        persist(type: .guests, markDirty: markDirty)
        persist(type: .reservations, markDirty: markDirty)
        persist(type: .deposits, markDirty: markDirty)
    }

    // MARK: - Reservation 操作

    func saveReservation(_ reservation: Reservation) {
        upsertReservation(reservation, markDirty: true)
    }

    func fetchActiveReservations() -> [Reservation] {
        reservations
            .filter { $0.isActive }
            .sorted { $0.checkInDate > $1.checkInDate }
            .map { fillRelations($0) }
    }

    func fetchActiveReservation(forRoomID roomID: String) -> Reservation? {
        guard let reservation = reservations.first(where: { $0.roomID == roomID && $0.isActive }) else { return nil }
        return fillRelations(reservation)
    }

    func deleteReservation(id: String) {
        removeReservation(id: id, markDirty: true)
    }

    func checkOut(reservationID: String) {
        markReservationCheckedOut(id: reservationID, at: Date(), markDirty: true)
    }

    func restoreActiveReservation(id: String) {
        if let idx = reservations.firstIndex(where: { $0.id == id }) {
            reservations[idx].isActive = true
            reservations[idx].actualCheckOut = nil
            persist(type: .reservations, markDirty: true)
        }
    }

    func fetchReservationHistory(forRoomID roomID: String, limit: Int = 50) -> [Reservation] {
        reservations
            .filter { $0.roomID == roomID && !$0.isActive }
            .sorted { $0.checkInDate > $1.checkInDate }
            .prefix(limit)
            .map { fillRelations($0) }
    }

    func mirrorReservation(_ reservation: Reservation) {
        upsertReservation(reservation, markDirty: false)
    }

    func mirrorReservations(_ reservations: [Reservation]) {
        upsertReservations(reservations, markDirty: false)
    }

    func mirrorDeleteReservation(id: String) {
        removeReservation(id: id, markDirty: false)
    }

    func mirrorCheckOut(reservationID: String, at timestamp: Date) {
        markReservationCheckedOut(id: reservationID, at: timestamp, markDirty: false)
    }

    func replaceReservations(_ newReservations: [Reservation]) {
        reservations = makeUnique(newReservations, id: \.id)
        persist(type: .reservations, markDirty: false)
    }

    private func removeReservation(id: String, markDirty: Bool) {
        reservations.removeAll { $0.id == id }
        deposits.removeAll { $0.reservationID == id }
        persist(type: .reservations, markDirty: markDirty)
        persist(type: .deposits, markDirty: markDirty)
    }

    private func markReservationCheckedOut(id: String, at timestamp: Date, markDirty: Bool) {
        if let idx = reservations.firstIndex(where: { $0.id == id }) {
            reservations[idx].isActive = false
            reservations[idx].actualCheckOut = timestamp
            persist(type: .reservations, markDirty: markDirty)
        }
    }

    // MARK: - Deposit 操作

    func deleteDeposit(id: String) {
        removeDeposit(id: id, markDirty: true)
    }

    func saveDepositRecord(_ deposit: DepositRecord) {
        upsertDeposit(deposit, markDirty: true)
    }

    func fetchDeposits(forReservationID reservationID: String) -> [DepositRecord] {
        deposits
            .filter { $0.reservationID == reservationID }
            .sorted { $0.timestamp < $1.timestamp }
    }

    func fetchAllDeposits() -> [DepositRecord] {
        deposits.sorted { $0.timestamp < $1.timestamp }
    }

    func mirrorDeposit(_ deposit: DepositRecord) {
        upsertDeposit(deposit, markDirty: false)
    }

    func mirrorDeposits(_ newDeposits: [DepositRecord]) {
        upsertDeposits(newDeposits, markDirty: false)
    }

    func mirrorDeleteDeposit(id: String) {
        removeDeposit(id: id, markDirty: false)
    }

    func replaceDeposits(_ newDeposits: [DepositRecord]) {
        deposits = makeUnique(newDeposits, id: \.id)
        persist(type: .deposits, markDirty: false)
    }

    private func removeDeposit(id: String, markDirty: Bool) {
        deposits.removeAll { $0.id == id }
        persist(type: .deposits, markDirty: markDirty)
    }

    // MARK: - 分析查询

    /// 获取所有预订记录（含活跃和历史）
    func fetchAllReservations() -> [Reservation] {
        reservations.map { fillRelations($0) }
    }

    /// 获取指定月份的已完成预订（按退房日期归入月份）
    func fetchReservationsForMonth(year: Int, month: Int) -> [Reservation] {
        let cal = Calendar.current
        return reservations
            .filter { res in
                guard !res.isActive else { return false }
                let checkOut = res.actualCheckOut ?? res.expectedCheckOut
                let y = cal.component(.year, from: checkOut)
                let m = cal.component(.month, from: checkOut)
                return y == year && m == month
            }
            .map { fillRelations($0) }
    }

    /// 获取指定月份中每一天的入住房间数（用于计算每日入住率）
    /// 返回 [day: occupiedRoomCount]，day 从 1 开始
    func fetchDailyOccupancy(year: Int, month: Int, totalRooms: Int) -> [(day: Int, count: Int)] {
        let cal = Calendar.current
        guard let firstOfMonth = cal.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = cal.range(of: .day, in: .month, for: firstOfMonth),
              let lastOfMonth = cal.date(byAdding: .month, value: 1, to: firstOfMonth) else { return [] }

        // 预过滤：只保留时间范围有交集的预订（大幅减少内循环）
        let relevantReservations = reservations.filter { res in
            let checkOut = res.actualCheckOut ?? res.expectedCheckOut
            return checkOut > firstOfMonth && res.checkInDate < lastOfMonth
        }

        var result: [(day: Int, count: Int)] = []
        for day in range {
            guard let date = cal.date(from: DateComponents(year: year, month: month, day: day)) else { continue }
            let dayStart = cal.startOfDay(for: date)
            // 按 roomID 去重，防止同一房间多条记录重复计数
            let occupiedRoomIDs = Set(relevantReservations.filter { res in
                let stayStart = cal.startOfDay(for: res.checkInDate)
                let checkOut = res.actualCheckOut ?? res.expectedCheckOut
                var stayEnd = cal.startOfDay(for: checkOut)
                if stayEnd <= stayStart {
                    stayEnd = cal.date(byAdding: .day, value: 1, to: stayStart) ?? stayStart
                }
                return stayStart <= dayStart && dayStart < stayEnd
            }.map(\.roomID))
            let count = occupiedRoomIDs.count
            result.append((day: day, count: min(count, totalRooms)))
        }
        return result
    }

    /// 获取房间总数
    func totalRoomCount() -> Int {
        rooms.count
    }

    // MARK: - 组合查询

    func fetchTodayCheckInCount() -> Int {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        return reservations.filter { $0.checkInDate >= startOfDay && $0.checkInDate < endOfDay }.count
    }

    func fetchTodayExpectedCheckOuts() -> [Reservation] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!
        return reservations
            .filter { $0.expectedCheckOut >= startOfDay && $0.expectedCheckOut < endOfDay && $0.isActive }
            .map { fillRelations($0) }
    }

    // MARK: - 辅助方法

    func replaceAllData(
        rooms newRooms: [Room],
        guests newGuests: [Guest],
        reservations newReservations: [Reservation],
        deposits newDeposits: [DepositRecord]
    ) {
        self.rooms = makeUnique(newRooms, id: \.id)
        self.guests = makeGuestMap(newGuests)
        self.reservations = makeUnique(newReservations, id: \.id)
        self.deposits = makeUnique(newDeposits, id: \.id)
        persistAll(markDirty: false)
    }

    private func fillRelations(_ reservation: Reservation) -> Reservation {
        var res = reservation
        res.guest = guests[res.guestID]
        res.room = rooms.first { $0.id == res.roomID }
        return res
    }

    private func upsertRoom(_ room: Room, markDirty: Bool) {
        if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
            rooms[idx] = room
        } else {
            rooms.append(room)
        }
        persist(type: .rooms, markDirty: markDirty)
    }

    private func upsertRooms(_ newRooms: [Room], markDirty: Bool) {
        for room in newRooms {
            if let idx = rooms.firstIndex(where: { $0.id == room.id }) {
                rooms[idx] = room
            } else {
                rooms.append(room)
            }
        }
        persist(type: .rooms, markDirty: markDirty)
    }

    private func setRoomStatus(roomID: String, status: RoomStatus, markDirty: Bool) {
        if let idx = rooms.firstIndex(where: { $0.id == roomID }) {
            rooms[idx].status = status
            persist(type: .rooms, markDirty: markDirty)
        }
    }

    private func removeRoom(id: String, markDirty: Bool) {
        rooms.removeAll { $0.id == id }
        persist(type: .rooms, markDirty: markDirty)
    }

    private func upsertGuest(_ guest: Guest, markDirty: Bool) {
        guard canPersist(guest) else { return }
        guests[guest.id] = guest
        persist(type: .guests, markDirty: markDirty)
    }

    private func upsertGuests(_ newGuests: [Guest], markDirty: Bool) {
        var didChange = false
        for guest in newGuests {
            guard canPersist(guest) else { continue }
            guests[guest.id] = guest
            didChange = true
        }
        if didChange {
            persist(type: .guests, markDirty: markDirty)
        }
    }

    private func upsertReservation(_ reservation: Reservation, markDirty: Bool) {
        if let idx = reservations.firstIndex(where: { $0.id == reservation.id }) {
            reservations[idx] = reservation
        } else {
            reservations.append(reservation)
        }
        persist(type: .reservations, markDirty: markDirty)
    }

    private func upsertReservations(_ newReservations: [Reservation], markDirty: Bool) {
        for reservation in newReservations {
            if let idx = reservations.firstIndex(where: { $0.id == reservation.id }) {
                reservations[idx] = reservation
            } else {
                reservations.append(reservation)
            }
        }
        persist(type: .reservations, markDirty: markDirty)
    }

    private func upsertDeposit(_ deposit: DepositRecord, markDirty: Bool) {
        if let idx = deposits.firstIndex(where: { $0.id == deposit.id }) {
            deposits[idx] = deposit
        } else {
            deposits.append(deposit)
        }
        persist(type: .deposits, markDirty: markDirty)
    }

    private func upsertDeposits(_ newDeposits: [DepositRecord], markDirty: Bool) {
        for deposit in newDeposits {
            if let idx = deposits.firstIndex(where: { $0.id == deposit.id }) {
                deposits[idx] = deposit
            } else {
                deposits.append(deposit)
            }
        }
        persist(type: .deposits, markDirty: markDirty)
    }

    private func makeGuestMap(_ guests: [Guest]) -> [String: Guest] {
        var result: [String: Guest] = [:]
        for guest in guests {
            guard canPersist(guest) else { continue }
            result[guest.id] = guest
        }
        return result
    }

    private func canPersist(_ guest: Guest) -> Bool {
        do {
            _ = try CodableGuest(guest)
            return true
        } catch {
            print("本地客人记录加密失败[\(guest.id)]: \(error.localizedDescription)")
            return false
        }
    }

    private func makeUnique<T>(_ items: [T], id: KeyPath<T, String>) -> [T] {
        var result: [String: T] = [:]
        for item in items {
            result[item[keyPath: id]] = item
        }
        return Array(result.values)
    }

    // MARK: - JSON 持久化

    private enum DataType: String {
        case rooms, guests, reservations, deposits
    }

    private func filePath(for type: DataType) -> URL {
        baseDir.appendingPathComponent("\(type.rawValue).json")
    }

    /// 批量操作时跳过磁盘写入，完成后调用 flushAll()
    var isBatchMode = false

    /// 批量操作后强制写入所有数据
    func flushAll() {
        isBatchMode = false
        persistAll(markDirty: true)
    }

    private func persistAll(markDirty: Bool) {
        persist(type: .rooms, markDirty: markDirty)
        persist(type: .guests, markDirty: markDirty)
        persist(type: .reservations, markDirty: markDirty)
        persist(type: .deposits, markDirty: markDirty)
    }

    private func persist(type: DataType, markDirty: Bool) {
        guard !isBatchMode else { return }
        if markDirty {
            BackupService.shared.markDirty()
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            let data: Data
            switch type {
            case .rooms: data = try encoder.encode(rooms.map { CodableRoom($0) })
            case .guests:
                let encodedGuests = try guests.values.map { try CodableGuest($0) }
                data = try encoder.encode(encodedGuests)
            case .reservations: data = try encoder.encode(reservations.map { CodableReservation($0) })
            case .deposits: data = try encoder.encode(deposits.map { CodableDeposit($0) })
            }
            try SecureStorageHelper.write(data, to: filePath(for: type), excludeFromBackup: true)
        } catch {
            print("本地存储写入失败[\(type.rawValue)]: \(error)")
        }
    }

    private func loadAll() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let data = try? Data(contentsOf: filePath(for: .rooms)),
           let items = try? decoder.decode([CodableRoom].self, from: data) {
            rooms = items.map { $0.toRoom() }
        }
        if let data = try? Data(contentsOf: filePath(for: .guests)),
           let items = try? decoder.decode([CodableGuest].self, from: data) {
            for g in items {
                do {
                    guests[g.id] = try g.toGuest()
                } catch {
                    print("本地客人记录解密失败[\(g.id)]: \(error.localizedDescription)")
                }
            }
        }
        if let data = try? Data(contentsOf: filePath(for: .reservations)),
           let items = try? decoder.decode([CodableReservation].self, from: data) {
            reservations = items.map { $0.toReservation() }
        }
        if let data = try? Data(contentsOf: filePath(for: .deposits)),
           let items = try? decoder.decode([CodableDeposit].self, from: data) {
            deposits = items.map { $0.toDeposit() }
        }
    }
}

// MARK: - Codable 适配器（因为原模型依赖 CloudKit，不能直接 Codable）

private struct CodableRoom: Codable {
    let id, roomNumber: String
    let floor: Int
    let roomType, orientation, status: String
    let pricePerNight: Double
    let weekendPrice: Double?
    let monthlyCost: Double?
    let notes: String?

    init(_ r: Room) {
        id = r.id; roomNumber = r.roomNumber; floor = r.floor
        roomType = r.roomType.rawValue; orientation = r.orientation.rawValue
        status = r.status.rawValue; pricePerNight = r.pricePerNight
        weekendPrice = r.weekendPrice; monthlyCost = r.monthlyCost; notes = r.notes
    }
    func toRoom() -> Room {
        Room(id: id, roomNumber: roomNumber, floor: floor,
             roomType: RoomType(rawValue: roomType) ?? .king,
             orientation: RoomOrientation(rawValue: orientation) ?? .south,
             status: RoomStatus(rawValue: status) ?? .vacant,
             pricePerNight: pricePerNight, weekendPrice: weekendPrice ?? 0,
             monthlyCost: monthlyCost ?? 0, notes: notes)
    }
}

private struct CodableGuest: Codable {
    let id, name, idType, idNumber, phone: String
    let email: String?
    let notes: String?

    init(_ g: Guest) throws {
        id = g.id; name = g.name; idType = g.idType.rawValue
        // 加密身份证号和手机号
        idNumber = try EncryptionHelper.encrypt(g.idNumber)
        phone = try EncryptionHelper.encrypt(g.phone)
        email = g.email
        notes = g.notes
    }
    func toGuest() throws -> Guest {
        Guest(id: id, name: name, idType: IDType(rawValue: idType) ?? .idCard,
              // 解密
              idNumber: try EncryptionHelper.decrypt(idNumber),
              phone: try EncryptionHelper.decrypt(phone),
              email: email,
              notes: notes)
    }
}

private struct CodableReservation: Codable {
    let id, guestID, roomID: String
    let checkInDate, expectedCheckOut: Date
    let actualCheckOut: Date?
    let isActive: Bool
    let numberOfGuests: Int
    let dailyRate: Double

    init(_ r: Reservation) {
        id = r.id; guestID = r.guestID; roomID = r.roomID
        checkInDate = r.checkInDate; expectedCheckOut = r.expectedCheckOut
        actualCheckOut = r.actualCheckOut; isActive = r.isActive
        numberOfGuests = r.numberOfGuests; dailyRate = r.dailyRate
    }
    func toReservation() -> Reservation {
        Reservation(id: id, guestID: guestID, roomID: roomID,
                    checkInDate: checkInDate, expectedCheckOut: expectedCheckOut,
                    actualCheckOut: actualCheckOut, isActive: isActive,
                    numberOfGuests: numberOfGuests, dailyRate: dailyRate)
    }
}

private struct CodableDeposit: Codable {
    let id, reservationID, type: String
    let amount: Double
    let paymentMethod: String?
    let timestamp: Date
    let operatorName, notes: String?

    init(_ d: DepositRecord) {
        id = d.id; reservationID = d.reservationID; type = d.type.rawValue
        amount = d.amount; paymentMethod = d.paymentMethod.rawValue
        timestamp = d.timestamp; operatorName = d.operatorName; notes = d.notes
    }
    func toDeposit() -> DepositRecord {
        DepositRecord(id: id, reservationID: reservationID,
                      type: DepositType(rawValue: type) ?? .collect,
                      amount: amount,
                      paymentMethod: PaymentMethod(rawValue: paymentMethod ?? "") ?? .cash,
                      timestamp: timestamp,
                      operatorName: operatorName, notes: notes)
    }
}
