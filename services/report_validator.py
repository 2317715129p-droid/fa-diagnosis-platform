"""Post-validation for LLM-generated FA diagnosis reports (anti-hallucination layer 3)."""

_REQUIRED_SECTIONS = (
    "【故障现象定位】",
    "【物理根因推导】",
    "【工程处置建议】",
    "【置信度评估】",
)

_CITATION_WARNING = "⚠️ 注意：本次推理未正确标注知识库溯源，请人工复核。"

_MANUAL_INSPECTION_MARKER = "无法定位，需人工硬件检测"

_SAFE_FALLBACK_TEMPLATE = """### 【故障现象定位】
- 故障部件：无法定位，需人工硬件检测
- 物理位置：待现场确认
- 报错代码：参见原始日志
- 故障等级：待评估

### 【物理根因推导】
知识库未检索到与当前故障特征匹配的历史案例，系统无法基于现有知识库进行可靠的物理根因推导。
依据：无（RAG 检索未命中，已触发安全回退）

### 【工程处置建议】
1. 紧急处置：建议暂停该设备关键业务负载，保留完整日志与告警快照
2. 根治方案：移交 FA 工程师进行现场硬件检测与诊断
3. 验证方法：人工确认故障部件后制定后续验证方案

### 【置信度评估】
- 诊断置信度：低
"""


def _append_block(report: str, block: str) -> str:
    if not report:
        return block
    separator = "" if report.endswith("\n") else "\n"
    return f"{report}{separator}\n{block}"


def _ensure_section_completeness(report: str) -> str:
    for section_title in _REQUIRED_SECTIONS:
        if section_title not in report:
            report = _append_block(
                report,
                f"{section_title}\n（LLM 未生成此章节，已自动补全，请人工复核）",
            )
    return report


def _ensure_citation_annotation(report: str) -> str:
    if "依据" not in report:
        report = _append_block(report, _CITATION_WARNING)
    return report


def _enforce_rag_fallback(report: str, features: dict) -> str:
    if features.get("rag_no_match") is True and _MANUAL_INSPECTION_MARKER not in report:
        return _SAFE_FALLBACK_TEMPLATE
    return report


def validate_and_fix_report(report: str, features: dict) -> str:
    """Post-validation for LLM-generated FA diagnosis reports.

    Applies three validation rules in order:

    1. Section title completeness check
    2. Citation annotation check
    3. RAG no-match fallback enforcement

    Args:
        report: Raw LLM-generated diagnosis report.
        features: Feature flags; may contain ``rag_no_match`` (bool).

    Returns:
        Validated and/or corrected report string.
    """
    report = _ensure_section_completeness(report)
    report = _ensure_citation_annotation(report)
    report = _enforce_rag_fallback(report, features)
    return report
