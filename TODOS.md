# TODOS

## Infrastructure

### CloudKit 重试 + 数据同步

**What:** CloudKit 降级到本地模式后，加定时重试机制，恢复后自动同步本地数据到云端。

**Why:** 当前 `isLocalMode = true` 后永远不会重试 CloudKit。前台 iPad 短暂断网后恢复，新数据只存本地，其他设备看不到——多设备场景无法使用。

**Context:** 已实现：1) 每 60 秒定时重试 CloudKit 可用性；2) 恢复后自动批量同步本地数据到 CloudKit（房间、客人、预订，分批 200 条上传）；3) 同步失败不影响读写。冲突处理使用 `.changedKeys` 策略（最后写入胜出）。

**Effort:** L
**Priority:** P1
**Depends on:** None
**Completed:** v1.0 (2026-03-20)

### 迁移到 SwiftData

**What:** 用 SwiftData 替代 JSON 文件存储，获得增量写入、索引查询、更好的查询性能。

**Why:** `LocalStorageService` 每次写入都重新序列化整个数组到 JSON 文件（`persist()` 方法），`fetchDailyOccupancy` 复杂度 O(天数 x 订单数)。100 间房运营半年后（~5000+ 订单）会明显变慢。

**Context:** 项目已要求 iOS 17+，SwiftData 可用。需要：1) 定义 @Model 类替代当前 struct+CodableAdapter；2) 替换 LocalStorageService 的所有读写方法为 SwiftData 查询；3) 写数据迁移逻辑把现有 JSON 文件导入 SwiftData；4) CloudKitService 的 fallback 改为调用 SwiftData。影响文件：所有 Model、LocalStorageService、CloudKitService。

**Effort:** XL
**Priority:** P2
**Depends on:** 重构服务层（TODO 4）先做完更省事

## Security

### 管理员密码迁移到 Keychain

**What:** 用 iOS Keychain 存储密码哈希替代 UserDefaults 明文存储。

**Why:** `AppSettings.managerPassword` 明文存在 UserDefaults（默认 "8888"），用 iExplorer 等工具即可读取。保护的是酒店营收数据（Analytics tab）。

**Context:** 已实现：1) KeychainHelper 封装 SecItemAdd/SecItemCopyMatching/SecItemDelete；2) SHA256 哈希存储密码；3) 首次启动自动迁移旧密码到 Keychain 并删除 UserDefaults 明文；4) `changePassword(to:)` 新 API。

**Effort:** S
**Priority:** P2
**Depends on:** None
**Completed:** v1.0 (2026-03-20)

## Data Integrity

### 入住操作补偿回滚

**What:** `CheckInViewModel.performCheckIn()` 4 步操作中任何步骤失败时，回滚已完成的步骤。

**Why:** 当前第 3 步（保存押金）成功但第 4 步（更新房间状态）失败时，会出现：押金已收但房间仍显示空房，导致重复分房和财务纠纷。

**Context:** 已实现：1) 每步成功后记录 ID；2) catch 块中调用 `rollback()` 按逆序删除（押金→订单→客人→恢复房间状态）；3) 新增 `deleteGuest/deleteReservation/deleteDeposit` 方法到 LocalStorageService 和 CloudKitService。

**Effort:** M
**Priority:** P1
**Depends on:** None
**Completed:** v1.0 (2026-03-20)

## Code Quality

### 拆分 RoomSetupView + 重构服务层

**What:** RoomSetupView（666 行）拆成 3 个文件；CloudKitService 用泛型减少 try/catch 重复；Model 直接 Codable 去掉适配器。

**Why:** RoomSetupView 包含管理员登录、房间 CRUD、测试数据生成 3 个不相关功能。CloudKitService 314 行中 ~60% 是重复的 fallback 模板。LocalStorageService 的 CodableRoom/CodableGuest 等适配器手动复制每个属性，新加字段容易遗漏。

**Context:** 部分完成：TestDataGenerator 已抽取为独立 Service（~200 行），RoomSetupView 从 666 行降至 ~440 行。剩余：CloudKitService 泛型 fallback 和 Codable 适配器去除留待 SwiftData 迁移时一并处理。

**Effort:** L
**Priority:** P2
**Depends on:** None
**Completed:** v1.0 (2026-03-20) — TestDataGenerator 抽取完成；CloudKit/Codable 重构推迟到 SwiftData 迁移

## Completed

### 全覆盖单元测试

**What:** 为所有 ViewModel、Model 计算属性、LocalStorageService 写单元测试。

**Why:** 当前零测试。AnalyticsViewModel 的营收计算、入住率、ADR、月度对比如果有 bug，老板看到的数据就是错的。CheckIn/CheckOut 涉及财务操作（押金收退），没有测试是最大风险。

**Context:** 新建 HotelFrontDeskTests target，7 个测试文件，97 个测试用例。覆盖：Reservation 计算、DepositSummary、AnalyticsViewModel 全部 KPI、CheckIn/CheckOut 表单验证、LocalStorageService CRUD + 分析查询、Date helpers、所有枚举。

**Effort:** M
**Priority:** P0
**Depends on:** None
**Completed:** v1.0 (2026-03-20)
