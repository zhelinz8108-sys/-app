"""
酒店前台 OCR 服务 - 基于 PaddleOCR
提供身份证/护照识别 API，供 iPad App 调用
"""

import re
import io
import logging
from fastapi import FastAPI, UploadFile, File, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from paddleocr import PaddleOCR
from PIL import Image

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="酒店前台 OCR 服务", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# 初始化 PaddleOCR（启动时加载模型，后续请求复用）
ocr_engine = PaddleOCR(use_angle_cls=True, lang="ch", show_log=False)


class OCRLineResult(BaseModel):
    text: str
    confidence: float
    position: list[list[float]]  # [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]


class ReceiptOCRResponse(BaseModel):
    success: bool
    lines: list[OCRLineResult] = []
    full_text: str = ""
    avg_confidence: float = 0.0
    line_count: int = 0
    error: str = ""


class IDCardResult(BaseModel):
    name: str = ""
    id_number: str = ""
    gender: str = ""
    ethnicity: str = ""
    birth_date: str = ""
    address: str = ""
    raw_texts: list[str] = []
    confidence: float = 0.0


class PassportResult(BaseModel):
    name: str = ""
    passport_number: str = ""
    nationality: str = ""
    birth_date: str = ""
    gender: str = ""
    raw_texts: list[str] = []
    confidence: float = 0.0


class OCRResponse(BaseModel):
    success: bool
    doc_type: str = ""  # "id_card" | "passport" | "unknown"
    id_card: IDCardResult | None = None
    passport: PassportResult | None = None
    error: str = ""


def parse_id_card(texts: list[str], confidences: list[float]) -> IDCardResult:
    """解析中国身份证 OCR 结果"""
    full_text = " ".join(texts)
    result = IDCardResult(raw_texts=texts)

    if confidences:
        result.confidence = sum(confidences) / len(confidences)

    # 提取身份证号：18位，最后一位可能是X
    id_match = re.search(r"\d{17}[\dXx]", full_text)
    if id_match:
        result.id_number = id_match.group().upper()

    # 提取姓名
    for i, text in enumerate(texts):
        text = text.strip()
        if "姓名" in text:
            name = text.replace("姓名", "").strip()
            if name:
                result.name = name
            elif i + 1 < len(texts):
                result.name = texts[i + 1].strip()
            break
        # OCR 可能把「姓名」拆成「姓」「名XX」
        if text.startswith("名") and len(text) > 1:
            candidate = text[1:].strip()
            if candidate and not result.name:
                result.name = candidate
                break

    # 如果没找到姓名标签，用启发式方法
    if not result.name:
        for text in texts:
            t = text.strip()
            if (2 <= len(t) <= 4
                    and all("\u4e00" <= c <= "\u9fff" for c in t)
                    and not any(kw in t for kw in ["姓名", "性别", "民族", "住址", "公民", "出生", "签发"])):
                result.name = t
                break

    # 提取性别
    for text in texts:
        if "男" in text and "姓" not in text:
            result.gender = "男"
            break
        if "女" in text and "姓" not in text:
            result.gender = "女"
            break

    # 提取民族
    ethnicity_match = re.search(r"民族\s*(\S+)", full_text)
    if ethnicity_match:
        result.ethnicity = ethnicity_match.group(1)

    # 提取出生日期
    birth_match = re.search(r"(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日", full_text)
    if birth_match:
        result.birth_date = f"{birth_match.group(1)}-{birth_match.group(2).zfill(2)}-{birth_match.group(3).zfill(2)}"
    else:
        # 从身份证号提取
        if result.id_number and len(result.id_number) == 18:
            y = result.id_number[6:10]
            m = result.id_number[10:12]
            d = result.id_number[12:14]
            result.birth_date = f"{y}-{m}-{d}"

    # 提取住址
    addr_parts = []
    capturing = False
    for text in texts:
        t = text.strip()
        if "住址" in t:
            addr_parts.append(t.replace("住址", "").strip())
            capturing = True
            continue
        if capturing:
            # 地址可能跨多行，遇到其他字段停止
            if any(kw in t for kw in ["公民", "身份", "号码", "签发"]) or re.match(r"\d{17}", t):
                break
            addr_parts.append(t)
    if addr_parts:
        result.address = "".join(addr_parts).strip()

    return result


def parse_passport(texts: list[str], confidences: list[float]) -> PassportResult:
    """解析护照 OCR 结果"""
    full_text = " ".join(texts)
    result = PassportResult(raw_texts=texts)

    if confidences:
        result.confidence = sum(confidences) / len(confidences)

    # 护照号（1-2个字母开头 + 纯数字，排除常见单词）
    excluded_words = {"PASSPORT", "REPUBLIC", "PEOPLES", "CHINESE", "AMERICAN",
                      "BRITISH", "JAPANESE", "KOREAN", "CANADIAN", "AUSTRALIAN",
                      "FRENCH", "GERMAN", "ITALIAN", "SURNAME", "GIVEN", "NAMES",
                      "NATIONALITY", "COUNTRY"}
    # 先尝试精确护照号格式：1-2个字母 + 6-9个数字
    passport_match = re.search(r"[A-Z]{1,2}\d{6,9}", full_text.upper())
    if passport_match:
        result.passport_number = passport_match.group()
    else:
        # 备选：字母数字混合，但排除常见单词
        for text in texts:
            t = text.strip().upper()
            if re.match(r"^[A-Z][A-Z0-9]{5,8}$", t) and t not in excluded_words:
                result.passport_number = t
                break

    # MRZ 行解析（护照底部机器可读区）
    mrz_lines = [t for t in texts if len(t) >= 30 and "<" in t]
    if len(mrz_lines) >= 2:
        line1 = mrz_lines[0].replace(" ", "")
        line2 = mrz_lines[1].replace(" ", "")

        # 从 MRZ 第一行提取姓名
        if "<<" in line1:
            name_part = line1.split("<<", 1)
            if len(name_part) >= 2:
                surname = name_part[0].replace("<", " ").strip()
                # 去掉类型码和国家码前缀
                if len(surname) > 5:
                    surname = surname[5:]
                given = name_part[1].replace("<", " ").strip()
                result.name = f"{given} {surname}".strip()

        # 从 MRZ 第二行提取护照号
        if len(line2) >= 9:
            result.passport_number = line2[:9].replace("<", "")

    # 简单文本匹配
    for text in texts:
        t = text.strip()
        if "nationality" in t.lower() or "国籍" in t:
            result.nationality = re.sub(r"(nationality|国籍)[:\s]*", "", t, flags=re.IGNORECASE).strip()
        if "sex" in t.lower() or "性别" in t:
            if "M" in t.upper() or "男" in t:
                result.gender = "M"
            elif "F" in t.upper() or "女" in t:
                result.gender = "F"

    return result


def detect_doc_type(texts: list[str]) -> str:
    """判断证件类型"""
    full_text = "".join(texts)

    # 身份证特征
    id_keywords = ["居民身份证", "姓名", "民族", "公民身份号码", "住址"]
    id_score = sum(1 for kw in id_keywords if kw in full_text)

    # 护照特征
    passport_keywords = ["PASSPORT", "护照", "REPUBLIC", "nationality", "MRZ"]
    passport_score = sum(1 for kw in passport_keywords if kw.lower() in full_text.lower())

    # 有18位身份证号也是强信号
    if re.search(r"\d{17}[\dXx]", full_text):
        id_score += 2

    if id_score > passport_score:
        return "id_card"
    elif passport_score > 0:
        return "passport"
    return "unknown"


@app.post("/ocr/id-card", response_model=OCRResponse)
async def scan_id_card(file: UploadFile = File(...)):
    """扫描身份证/护照，返回结构化信息"""
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传图片文件")

    try:
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))

        # PaddleOCR 识别（传文件路径或numpy array）
        import numpy as np
        img_array = np.array(image)
        results = ocr_engine.ocr(img_array)

        if not results or not results[0]:
            return OCRResponse(success=False, error="未识别到文字，请重新拍照")

        texts = []
        confidences = []
        for line in results[0]:
            text = line[1][0]
            conf = line[1][1]
            texts.append(text)
            confidences.append(conf)

        logger.info(f"OCR识别到 {len(texts)} 行文字: {texts}")

        # 判断证件类型
        doc_type = detect_doc_type(texts)

        if doc_type == "id_card":
            id_result = parse_id_card(texts, confidences)
            if not id_result.id_number:
                return OCRResponse(
                    success=False,
                    doc_type=doc_type,
                    id_card=id_result,
                    error="未识别到身份证号，请对准身份证正面重试",
                )
            return OCRResponse(success=True, doc_type=doc_type, id_card=id_result)

        elif doc_type == "passport":
            passport_result = parse_passport(texts, confidences)
            if not passport_result.passport_number:
                return OCRResponse(
                    success=False,
                    doc_type=doc_type,
                    passport=passport_result,
                    error="未识别到护照号，请对准护照信息页重试",
                )
            return OCRResponse(success=True, doc_type=doc_type, passport=passport_result)

        else:
            return OCRResponse(
                success=False,
                doc_type="unknown",
                error="未识别到有效证件，请拍摄身份证正面或护照信息页",
            )

    except Exception as e:
        logger.exception("OCR处理失败")
        return OCRResponse(success=False, error=f"识别失败: {str(e)}")


@app.post("/ocr/receipt", response_model=ReceiptOCRResponse)
async def scan_receipt(file: UploadFile = File(...)):
    """通用OCR识别，返回所有检测到的文字行及位置和置信度"""
    if not file.content_type or not file.content_type.startswith("image/"):
        raise HTTPException(status_code=400, detail="请上传图片文件")

    try:
        contents = await file.read()
        image = Image.open(io.BytesIO(contents))

        import numpy as np
        img_array = np.array(image)
        results = ocr_engine.ocr(img_array)

        if not results or not results[0]:
            return ReceiptOCRResponse(success=False, error="未识别到文字，请重新拍照")

        lines = []
        total_conf = 0.0
        text_parts = []

        for line in results[0]:
            position = line[0]  # [[x1,y1],[x2,y2],[x3,y3],[x4,y4]]
            text = line[1][0]
            conf = line[1][1]

            lines.append(OCRLineResult(
                text=text,
                confidence=conf,
                position=position,
            ))
            total_conf += conf
            text_parts.append(text)

        avg_conf = total_conf / len(lines) if lines else 0.0

        logger.info(f"Receipt OCR: {len(lines)} lines, avg confidence {avg_conf:.3f}")

        return ReceiptOCRResponse(
            success=True,
            lines=lines,
            full_text="\n".join(text_parts),
            avg_confidence=avg_conf,
            line_count=len(lines),
        )

    except Exception as e:
        logger.exception("Receipt OCR处理失败")
        return ReceiptOCRResponse(success=False, error=f"识别失败: {str(e)}")


@app.get("/health")
async def health():
    return {"status": "ok", "engine": "PaddleOCR"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8089)
