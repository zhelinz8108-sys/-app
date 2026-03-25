# Codex 全面 Debug 任务说明

## 项目概述

**HotelFrontDesk** — 酒店前台管理 iPad App，使用 SwiftUI + CloudKit 构建。
- **iOS 最低版本:** 17.0
- **语言:** Swift 5.9
- **架构:** MVVM（Model-ViewModel-View）
- **数据存储:** CloudKit（主）+ JSON 文件本地存储（降级）+ Keychain（密码）
- **国际化:** 中文（zh-Hans）/ 英文（en）
- **测试:** 168 个单元测试，全部通过
- **编译:** 零 warning，零 error

## 核心功能

1. **房间管理** — 按状态（空房/预订/入住/清洁/维护）查看房间网格
2. **入住/退房** — 客人登记、身份证扫描（Vision OCR）、押金收取/退还
3. **数据分析** — 月度 KPI（营收、入住率、ADR、同比）
4. **OTA 预订** — 美团/飞猪/携程/Booking/Agoda/直客
5. **夜审** — 日终审核、延住请求、逾期检查
6. **PDF 报表** — 日营收报表、月度运营报表
7. **员工管理** — 角色权限（经理=全功能，员工=入住退房）
8. **房间设置** — 房型/楼层/朝向/定价配置
9. **特殊定价** — 节假日/旺季房价覆盖
10. **备份** — iCloud 自动备份（10分钟间隔）+ 手动导入导出

## 项目结构

```
HotelFrontDesk/
├── HotelFrontDeskApp.swift              # App 入口
├── ContentView.swift                    # 主 Tab 导航（仪表盘/房间/入住/退房/预订/分析/设置）
├── Models/                              # 数据模型（9个文件）
│   ├── Room.swift                       # 房间：roomNumber, floor, type, status, pricing
│   ├── Guest.swift                      # 客人：name, idType, idNumber(加密), phone(加密)
│   ├── Reservation.swift                # 预订：checkIn/Out, dailyRate, nightsStayed, totalRevenue
│   ├── DepositRecord.swift              # 押金：collect/refund, amount, paymentMethod
│   ├── Staff.swift                      # 员工：username, passwordHash(PBKDF2), role
│   ├── AppSettings.swift                # 管理员模式 + 密码管理
│   ├── OTABooking.swift                 # OTA 预订
│   ├── OperationLog.swift               # 操作日志
│   └── SpecialDatePrice.swift           # 特殊日期定价
├── Services/                            # 业务逻辑（14个文件）
│   ├── CloudKitService.swift            # CloudKit 同步 + 本地降级（437行）
│   ├── LocalStorageService.swift        # JSON 文件持久化（389行）
│   ├── StaffService.swift               # 员工认证 & CRUD（215行）
│   ├── PricingService.swift             # 动态定价（特殊日>周末>工作日）
│   ├── NightAuditService.swift          # 夜审服务
│   ├── OperationLogService.swift        # 操作日志服务
│   ├── OTABookingService.swift          # OTA 预订管理
│   ├── BackupService.swift              # iCloud 备份
│   ├── ReportGenerator.swift            # PDF 报表生成（487行）
│   ├── RoomLockService.swift            # 房间并发锁（防重复入住）
│   ├── KeychainHelper.swift             # PBKDF2 密码哈希 + Keychain 存储
│   ├── EncryptionHelper.swift           # AES-256 PII 加密
│   ├── LanguageService.swift            # 运行时语言切换
│   └── TestDataGenerator.swift          # 测试数据生成
├── ViewModels/                          # UI 状态管理（5个文件）
│   ├── AnalyticsViewModel.swift         # KPI 计算（321行）
│   ├── CheckInViewModel.swift           # 入住表单 + 验证（295行）
│   ├── CheckOutViewModel.swift          # 退房流程
│   ├── DashboardViewModel.swift         # 概览统计
│   └── RoomListViewModel.swift          # 房间过滤
├── Views/                               # SwiftUI 视图（~6,200行）
│   ├── Dashboard/DashboardView.swift    # 概览面板
│   ├── Rooms/                           # 房间网格、卡片、详情、日历、转房
│   ├── CheckIn/                         # 入住表单、客人信息、房间选择、身份证扫描
│   ├── CheckOut/                        # 退房、押金退还
│   ├── Bookings/                        # OTA 预订列表、表单
│   ├── Analytics/                       # KPI 面板、夜审、报表导出
│   ├── Settings/                        # 房间设置、备份、特殊定价
│   ├── Staff/                           # 员工登录、管理
│   ├── Logs/OperationLogView.swift      # 操作日志
│   └── Shared/                          # StatCard、收据拍照、缩略图
├── Utilities/
│   ├── Extensions/
│   │   ├── Color+Theme.swift            # 奢华主题色板（深海蓝#1B2838、金色#C5A55A）
│   │   └── Date+Helpers.swift           # 日期格式化工具
│   ├── Validators.swift                 # 手机号/身份证验证
│   └── ErrorHelper.swift                # 错误格式化
└── Resources/
    ├── en.lproj/Localizable.strings     # 英文翻译
    └── zh-Hans.lproj/Localizable.strings # 中文翻译

HotelFrontDeskTests/                     # 测试套件（14个文件，168个测试）
├── AnalyticsCalculationTests.swift      # KPI 数学验证
├── CheckInValidationTests.swift         # 入住表单验证
├── CheckOutValidationTests.swift        # 退房逻辑验证
├── LocalStorageServiceTests.swift       # CRUD + 查询
├── DataIntegrityTests.swift             # 3 个月模拟场景
├── DepositTests.swift                   # 押金收退
├── PricingTests.swift                   # 动态定价
├── ReservationTests.swift               # 预订计算
├── RoomModelTests.swift                 # 枚举行为
├── SecurityTests.swift                  # 认证 & 加密
├── StorageStressTests.swift             # 大数据集
├── WorkflowIntegrationTests.swift       # 端到端流程
├── DateHelpersTests.swift               # 日期工具
└── EdgeCaseTests.swift                  # 边界条件
```

## 关键数据模型关系

```
Room (1) ←→ (N) Reservation
Guest (1) ←→ (N) Reservation
Reservation (1) ←→ (N) DepositRecord
OTABooking (1) ←→ (0..1) Room (assignedRoomID)
Staff → 操作所有实体
OperationLog ← 记录所有操作
SpecialDatePrice → 覆盖 Room 定价
```

## 关键枚举

```swift
RoomStatus: vacant, reserved, occupied, cleaning, maintenance
RoomType: king(大床房), twin(双床房), suite(套房)
RoomOrientation: south, north, east, west, southeast, southwest, northeast, northwest
IDType: idCard, passport, other
PaymentMethod: cash, wechat, alipay, bankCard, pos, transfer
StaffRole: manager, employee
DepositType: collect, refund
BookingStatus: pending, confirmed, checkedIn, cancelled, noShow
OTAPlatform: meituan, fliggy, ctrip, booking, agoda, direct
```

## 关键计算属性（容易出 Bug 的地方）

```swift
// Reservation
nightsStayed = max(1, Calendar.current.dateComponents([.day], from: checkInDate, to: actualCheckOut ?? expectedCheckOut).day!)
totalRevenue = Double(nightsStayed) * dailyRate

// DepositRecord 汇总
balance = totalCollected - totalRefunded

// AnalyticsViewModel
occupancyRate = occupiedRoomNights / totalAvailableRoomNights × 100%
adr (平均房价) = monthlyRevenue / totalOccupiedNights
monthOverMonth = (thisMonth - lastMonth) / lastMonth × 100%
```

## 安全机制

- **密码:** PBKDF2 100,000 次迭代 + 随机 salt，存 Keychain
- **PII 加密:** 客人身份证号和手机号 AES-256 加密后存 CloudKit
- **审计日志:** 所有操作记录时间戳、操作人、角色
- **登录锁定:** 5 次失败 → 5 分钟锁定
- **备份排除:** Staff.json 不上传 iCloud（含密码哈希）
- **并发控制:** RoomLockService 防止重复分配同一房间

## 当前未提交的改动（工作区脏状态）

以下文件有未提交的修改，可能包含进行中的工作或未完成的 bug 修复：

| 文件 | 变更概述 |
|------|---------|
| ContentView.swift | Tab 导航调整 |
| Models/DepositRecord.swift | 押金模型修改 |
| Models/Room.swift | 房间模型修改 |
| Models/Staff.swift | 新增员工属性 |
| Services/LanguageService.swift | 语言服务重构 |
| Services/StaffService.swift | 员工服务修改 |
| Services/TestDataGenerator.swift | 测试数据生成器扩展（+103行） |
| Utilities/Extensions/Color+Theme.swift | 主题色微调 |
| Views/Analytics/AnalyticsView.swift | 分析面板 UI 改动 |
| Views/Dashboard/DashboardView.swift | 仪表盘 UI 改动 |
| Views/Rooms/RoomCardView.swift | 房间卡片 UI 改动 |
| Views/Settings/RoomSetupView.swift | 房间设置修改 |
| Views/Shared/StatCard.swift | 统计卡片组件修改 |
| Views/Staff/StaffLoginView.swift | 员工登录 UI 改动 |
| HotelFrontDeskTests/DataIntegrityTests.swift | 新增测试文件（未追踪） |

## Debug 任务清单

### 第一阶段：编译 & 测试验证

1. **确认编译通过** — `xcodebuild build` 零 warning 零 error
2. **运行全部 168 个测试** — `xcodebuild test`，确认全部通过
3. **如果有测试失败，记录并修复**

### 第二阶段：数据层 Bug 排查

4. **LocalStorageService 数据一致性**
   - `persist()` 每次写入重新序列化整个数组到 JSON 文件，检查是否有并发写入导致数据丢失的风险
   - `fetchDailyOccupancy()` 复杂度 O(天数 × 订单数)，检查边界日期处理是否正确
   - 检查 delete 方法（deleteGuest, deleteReservation, deleteDeposit）是否正确清理关联数据

5. **CloudKitService 降级逻辑**
   - 检查 `isLocalMode` 切换时是否有竞态条件
   - 验证 60 秒重试机制是否正确恢复 CloudKit
   - 检查批量同步（200 条/批）是否有遗漏数据

6. **入住回滚补偿（CheckInViewModel.performCheckIn）**
   - 验证 4 步操作（保存客人→保存预订→保存押金→更新房间状态）失败时回滚是否完整
   - 检查回滚过程中如果删除操作也失败，是否有兜底处理

7. **PricingService 定价优先级**
   - 验证特殊日期 > 周末价 > 工作日价的优先级是否正确
   - 检查跨日期入住时（如入住日是特殊日期，第二天不是）的价格计算

### 第三阶段：业务逻辑 Bug 排查

8. **Reservation.nightsStayed 计算**
   - 边界：当天入住当天退房 = 1 晚（确认 `max(1, ...)` 是否正确）
   - 跨月、跨年的住宿天数计算
   - `actualCheckOut` 为 nil 时使用 `expectedCheckOut` 的行为

9. **AnalyticsViewModel KPI 计算**
   - 入住率计算：分母（totalAvailableRoomNights）是否排除了维护中的房间
   - ADR 计算：分母为 0 时是否有除零保护
   - 月度对比：上月数据为 0 时的环比计算
   - 日营收数据是否与月度汇总一致

10. **押金管理**
    - 退房时押金余额计算是否正确（总收 - 总退）
    - 部分退款场景是否处理正确
    - 押金记录与预订的关联是否可靠

11. **夜审服务（NightAuditService）**
    - 逾期预订检测逻辑是否正确
    - 延住请求处理是否更新了 expectedCheckOut
    - 日终审核是否正确锁定当日数据

12. **OTA 预订流程**
    - 预订状态机转换是否完整（pending→confirmed→checkedIn/cancelled/noShow）
    - 分配房间后预订状态是否正确更新
    - 取消预订是否释放已分配的房间

### 第四阶段：UI & 交互 Bug 排查

13. **房间状态流转**
    - vacant → reserved → occupied → cleaning → vacant 的完整生命周期
    - maintenance 状态的进入和退出是否正确
    - 房间转移（RoomTransferView）是否正确更新两个房间的状态

14. **员工登录**
    - 5 次失败锁定是否在 5 分钟后正确解锁
    - 经理/员工角色权限是否正确隔离
    - 登出后是否清理所有敏感状态

15. **多语言**
    - 运行时语言切换是否立即生效（不需重启）
    - 所有用户可见字符串是否都有中英文翻译
    - 数字/日期/货币格式是否跟随语言设置

16. **表单验证**
    - 入住表单：必填字段、手机号格式、身份证格式
    - 检查是否有未处理的 optional 强制解包（force unwrap）
    - 表单提交后是否正确清空/重置状态

### 第五阶段：性能 & 安全审查

17. **内存 & 性能**
    - 大量房间（100+）时网格渲染性能
    - JSON 序列化/反序列化在大数据集下的表现
    - 是否有内存泄漏（循环引用、未释放的 closure）

18. **安全审查**
    - 检查是否有硬编码的密码或密钥
    - 加密 key 的来源和管理是否安全
    - 日志中是否意外打印了敏感信息（身份证号、手机号）
    - Keychain 访问权限是否设置正确

19. **线程安全**
    - `@MainActor` 标注是否完整
    - async/await 使用是否正确
    - 单例 Service 的并发访问是否安全

### 第六阶段：代码质量

20. **Dead Code 清理**
    - 查找未使用的函数、变量、导入
    - 检查是否有注释掉的代码块

21. **Error Handling**
    - 检查所有 `try` 是否有对应的 catch
    - 用户可见的错误信息是否友好（而非技术堆栈）
    - 网络错误是否有合理的重试或提示

22. **边界条件**
    - 空数据状态（零房间、零预订）下是否 crash
    - 极端输入（超长字符串、负数金额、远未来日期）
    - 时区处理：跨时区使用时日期计算是否正确

## 构建 & 测试命令

```bash
# 编译
xcodebuild build \
  -scheme HotelFrontDesk \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)'

# 运行测试
xcodebuild test \
  -scheme HotelFrontDesk \
  -destination 'platform=iOS Simulator,name=iPad Air 11-inch (M3)'
```

## 期望输出

完成 debug 后，请提供：

1. **Bug 报告列表** — 每个 bug 包含：文件路径、行号、问题描述、严重程度（Critical/High/Medium/Low）、修复建议
2. **已修复的 Bug** — 列出你直接修复的问题及修改内容
3. **安全风险** — 任何安全相关发现
4. **性能瓶颈** — 需要优化的热点
5. **代码质量建议** — 可维护性改进（不要大规模重构，只标注问题）

## 注意事项

- **不要做大规模重构**，只修复明确的 Bug
- **不要修改测试数据或测试逻辑**，除非测试本身有 Bug
- **不要修改 UI 设计/布局**，除非发现功能性 Bug
- **保持所有 168 个测试通过**
- **修复后重新运行全部测试确认无回归**
- **优先修复 Critical 和 High 级别的 Bug**
- 项目使用中文注释和中文 UI，保持一致
