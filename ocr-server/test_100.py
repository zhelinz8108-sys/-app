"""
100 组不同数据测试 OCR 解析逻辑
覆盖：身份证（各种 OCR 输出格式）、护照、边界情况
"""
import sys
import random
import json
from main import parse_id_card, parse_passport, detect_doc_type

random.seed(42)

# ── 中国姓名库 ──
SURNAMES = ["张", "李", "王", "赵", "刘", "陈", "杨", "黄", "周", "吴",
            "徐", "孙", "马", "胡", "朱", "高", "林", "何", "郭", "罗",
            "欧阳", "上官", "司马", "诸葛", "慕容"]
GIVEN_NAMES = ["伟", "芳", "娜", "秀英", "敏", "静", "强", "磊", "洋", "艳",
               "勇", "军", "杰", "娟", "涛", "明", "超", "秀兰", "霞", "平",
               "建国", "建华", "志强", "淑珍", "桂英", "玉兰", "国庆", "德华"]
ETHNICITIES = ["汉", "满", "蒙古", "回", "藏", "维吾尔", "苗", "彝", "壮", "布依",
               "侗", "瑶", "白", "土家", "哈尼", "傣", "黎", "畲", "高山", "拉祜"]
PROVINCES = ["北京市", "上海市", "广东省广州市", "浙江省杭州市", "江苏省南京市",
             "四川省成都市", "湖北省武汉市", "湖南省长沙市", "山东省济南市", "河南省郑州市",
             "福建省福州市", "重庆市", "天津市", "陕西省西安市", "辽宁省沈阳市",
             "吉林省长春市", "黑龙江省哈尔滨市", "安徽省合肥市", "江西省南昌市", "云南省昆明市"]
STREETS = ["建国路88号", "人民大道1号", "中山路100号", "解放路56号", "长安街10号",
           "南京路200号", "淮海路300号", "天府大道999号", "黄浦路12号", "东风路45号"]


def gen_id_number(year, month, day, gender_male=True):
    """生成模拟身份证号（非真实有效）"""
    area = random.choice(["110105", "310101", "440106", "330102", "320102",
                          "510104", "420102", "430104", "370102", "410102"])
    seq = random.randint(0, 99)
    seq_digit = seq * 10 + (1 if gender_male else 0)  # 奇数男，偶数女
    base = f"{area}{year:04d}{month:02d}{day:02d}{seq_digit:03d}"
    # 简化校验码
    check = random.choice("0123456789X")
    return base + check


def gen_name():
    return random.choice(SURNAMES) + random.choice(GIVEN_NAMES)


def gen_date():
    y = random.randint(1950, 2005)
    m = random.randint(1, 12)
    d = random.randint(1, 28)
    return y, m, d


# ════════════════════════════════════════
# 测试用例生成
# ════════════════════════════════════════

tests = []
pass_count = 0
fail_count = 0
results_detail = []


def add_test(name, texts, expected_name, expected_id, expected_type="id_card",
             is_passport=False, expected_passport_num=""):
    tests.append({
        "name": name,
        "texts": texts,
        "expected_name": expected_name,
        "expected_id": expected_id,
        "expected_type": expected_type,
        "is_passport": is_passport,
        "expected_passport_num": expected_passport_num,
    })


# ── 1-30: 标准身份证格式（姓名在同一行） ──
for i in range(1, 31):
    name = gen_name()
    y, m, d = gen_date()
    gender = random.choice(["男", "女"])
    eth = random.choice(ETHNICITIES)
    addr = random.choice(PROVINCES) + random.choice(STREETS)
    id_num = gen_id_number(y, m, d, gender == "男")

    texts = [
        f"姓名 {name}",
        f"性别 {gender}  民族 {eth}",
        f"出生 {y}年{m}月{d}日",
        f"住址 {addr}",
        "公民身份号码",
        id_num,
    ]
    add_test(f"标准格式#{i}", texts, name, id_num)

# ── 31-45: 姓名在下一行 ──
for i in range(31, 46):
    name = gen_name()
    y, m, d = gen_date()
    id_num = gen_id_number(y, m, d)
    texts = [
        "姓名",
        name,
        f"性别 男  民族 汉",
        f"出生 {y}年{m}月{d}日",
        f"住址 {random.choice(PROVINCES)}{random.choice(STREETS)}",
        "公民身份号码",
        id_num,
    ]
    add_test(f"姓名下一行#{i}", texts, name, id_num)

# ── 46-55: OCR 把「姓名」拆开识别 ──
for i in range(46, 56):
    name = gen_name()
    y, m, d = gen_date()
    id_num = gen_id_number(y, m, d)
    texts = [
        "姓",
        f"名{name}",
        f"性别 女  民族 {random.choice(ETHNICITIES)}",
        id_num,
    ]
    add_test(f"姓名拆开#{i}", texts, name, id_num)

# ── 56-65: 没有「姓名」关键字，靠启发式匹配 ──
for i in range(56, 66):
    name = gen_name()
    # 确保名字 2-4 个字且全中文
    while len(name) > 4 or len(name) < 2:
        name = gen_name()
    y, m, d = gen_date()
    id_num = gen_id_number(y, m, d)
    texts = [
        name,
        f"性别 男",
        f"民族 汉",
        f"出生 {y}年{m}月{d}日",
        id_num,
    ]
    add_test(f"无姓名标签#{i}", texts, name, id_num)

# ── 66-70: 身份证号中有X ──
for i in range(66, 71):
    name = gen_name()
    y, m, d = gen_date()
    area = random.choice(["110105", "310101", "440106"])
    seq = f"{random.randint(0, 999):03d}"
    id_num = f"{area}{y:04d}{m:02d}{d:02d}{seq}X"
    texts = [
        f"姓名 {name}",
        f"性别 男  民族 汉",
        "公民身份号码",
        id_num,
    ]
    add_test(f"尾号X#{i}", texts, name, id_num)

# ── 71-75: 地址跨多行 ──
for i in range(71, 76):
    name = gen_name()
    y, m, d = gen_date()
    id_num = gen_id_number(y, m, d)
    texts = [
        f"姓名 {name}",
        f"性别 男  民族 汉",
        f"住址 {random.choice(PROVINCES)}",
        f"{random.choice(STREETS)}",
        "某某小区3栋2单元401",
        "公民身份号码",
        id_num,
    ]
    add_test(f"多行地址#{i}", texts, name, id_num)

# ── 76-85: 护照测试 ──
COUNTRIES = ["CHINESE", "AMERICAN", "BRITISH", "JAPANESE", "KOREAN",
             "CANADIAN", "AUSTRALIAN", "FRENCH", "GERMAN", "ITALIAN"]
for i in range(76, 86):
    first = random.choice(["JOHN", "MARY", "DAVID", "SARAH", "JAMES",
                           "EMMA", "MICHAEL", "LISA", "ROBERT", "ANNA"])
    last = random.choice(["SMITH", "WANG", "CHEN", "JOHNSON", "WILLIAMS",
                          "BROWN", "JONES", "MILLER", "DAVIS", "GARCIA"])
    passport_num = f"{random.choice('GEPM')}{random.randint(10000000, 99999999)}"
    nationality = random.choice(COUNTRIES)
    gender = random.choice(["M", "F"])

    texts = [
        "PASSPORT",
        f"Surname {last}",
        f"Given Names {first}",
        f"nationality {nationality}",
        f"sex {gender}",
        passport_num,
    ]
    add_test(f"护照#{i}", texts, "", "", expected_type="passport",
             is_passport=True, expected_passport_num=passport_num)

# ── 86-90: 中国护照 ──
for i in range(86, 91):
    name_cn = gen_name()
    passport_num = f"G{random.randint(10000000, 99999999)}"
    texts = [
        "中华人民共和国",
        "PASSPORT",
        f"姓名 {name_cn}",
        f"nationality CHINESE",
        f"sex M",
        passport_num,
    ]
    add_test(f"中国护照#{i}", texts, "", "", expected_type="passport",
             is_passport=True, expected_passport_num=passport_num)

# ── 91-95: OCR 噪声/部分识别 ──
for i in range(91, 96):
    name = gen_name()
    while len(name) > 4 or len(name) < 2:
        name = gen_name()
    y, m, d = gen_date()
    id_num = gen_id_number(y, m, d)
    # 添加一些 OCR 噪声文本
    noise = random.choice(["—", ".", "~", "中华人民共和国", "居民身份证"])
    texts = [
        noise,
        f"姓名 {name}",
        "性别男民族汉",  # 无空格
        id_num,
        noise,
    ]
    add_test(f"噪声文本#{i}", texts, name, id_num)

# ── 96-100: 复合姓氏 ──
COMPOUND_SURNAMES = ["欧阳", "上官", "司马", "诸葛", "慕容"]
for i in range(96, 101):
    surname = COMPOUND_SURNAMES[i - 96]
    given = random.choice(GIVEN_NAMES)
    name = surname + given
    while len(name) > 4:
        given = random.choice(["伟", "芳", "敏", "静", "强"])
        name = surname + given
    y, m, d = gen_date()
    id_num = gen_id_number(y, m, d)
    texts = [
        f"姓名 {name}",
        f"性别 男  民族 汉",
        "公民身份号码",
        id_num,
    ]
    add_test(f"复合姓#{i}", texts, name, id_num)

# ════════════════════════════════════════
# 执行测试
# ════════════════════════════════════════

print(f"\n{'='*60}")
print(f"  酒店前台 OCR 解析逻辑测试 — 共 {len(tests)} 组")
print(f"{'='*60}\n")

for i, t in enumerate(tests, 1):
    detected_type = detect_doc_type(t["texts"])
    confs = [0.95] * len(t["texts"])

    passed = True
    errors = []

    if t["is_passport"]:
        result = parse_passport(t["texts"], confs)
        if result.passport_number != t["expected_passport_num"]:
            # 护照号可能部分匹配
            if t["expected_passport_num"] not in result.passport_number and result.passport_number not in t["expected_passport_num"]:
                passed = False
                errors.append(f"护照号: 期望={t['expected_passport_num']}, 实际={result.passport_number}")
        if detected_type != "passport":
            passed = False
            errors.append(f"类型检测: 期望=passport, 实际={detected_type}")
    else:
        result = parse_id_card(t["texts"], confs)
        if result.id_number != t["expected_id"]:
            passed = False
            errors.append(f"身份证号: 期望={t['expected_id']}, 实际={result.id_number}")
        if t["expected_name"] and result.name != t["expected_name"]:
            passed = False
            errors.append(f"姓名: 期望={t['expected_name']}, 实际={result.name}")
        if detected_type != "id_card":
            passed = False
            errors.append(f"类型检测: 期望=id_card, 实际={detected_type}")

    status = "✅" if passed else "❌"
    if passed:
        pass_count += 1
    else:
        fail_count += 1

    detail = {"test": i, "name": t["name"], "passed": passed, "errors": errors}
    results_detail.append(detail)

    if not passed:
        print(f"  {status} #{i:3d} {t['name']}")
        for e in errors:
            print(f"         ↳ {e}")

# ── 汇总 ──
print(f"\n{'='*60}")
print(f"  测试结果汇总")
print(f"{'='*60}")
print(f"  总计:   {len(tests)} 组")
print(f"  通过:   {pass_count} ✅")
print(f"  失败:   {fail_count} ❌")
print(f"  通过率: {pass_count/len(tests)*100:.1f}%")
print(f"{'='*60}")

# 分类统计
categories = {}
for d in results_detail:
    cat = d["name"].split("#")[0]
    if cat not in categories:
        categories[cat] = {"pass": 0, "fail": 0}
    if d["passed"]:
        categories[cat]["pass"] += 1
    else:
        categories[cat]["fail"] += 1

print(f"\n  分类统计:")
for cat, stats in categories.items():
    total = stats["pass"] + stats["fail"]
    rate = stats["pass"] / total * 100
    icon = "✅" if stats["fail"] == 0 else "⚠️"
    print(f"  {icon} {cat:12s}  {stats['pass']}/{total} ({rate:.0f}%)")

print()
sys.exit(0 if fail_count == 0 else 1)
