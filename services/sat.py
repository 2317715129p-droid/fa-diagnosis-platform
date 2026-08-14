"""
日志预处理模块（Dify 工作流 · 第一层：通用正则提取）

用途：将非结构化硬件日志转为结构化故障特征 JSON，供 RAG / LLM 下游节点使用。
可直接粘贴到 Dify「Python 代码」节点；入口函数为 main(log_text, server_id)。

已知 Bug 修复：
1. MCE 续行判断统一 IGNORECASE（IBM BANK 全大写）
2. STATUS 寄存器值支持无 0x 前缀，提取后统一补全
3. PCIe AER 使用 \\bAER\\b，避免 AERR 误判
4. Corrected 优先于 IERR/Uncorrected，避免等级误判
5. 始终输出 rag_query / llm_context
"""

from __future__ import annotations

import json
import re
from typing import Any

# ---------------------------------------------------------------------------
# 降噪词表
# ---------------------------------------------------------------------------

_NOISE_PATTERNS = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"\bsystemd\b",
        r"\bcron\b",
        r"\bsshd\b",
        r"\bdhcp\b",
        r"\bNetworkManager\b",
        r"\bext[234]\b",
        r"\bxfs\b",
        r"\bnfs\b",
        r"\baudit\b",
        r"\bkernel:\s*\[.*\]\s*(?:INFO|DEBUG)",
    ]
]

_HARDWARE_KEEP_PATTERNS = [
    re.compile(p, re.IGNORECASE)
    for p in [
        r"Hardware\s+Error",
        r"Hardware\s+event",
        r"\bMCE\b",
        r"Machine\s+Check",
        r"\bEDAC\b",
        r"Temperature",
        r"\bFan\b",
        r"Voltage",
        r"\bSMART\b",
        r"pcieport",
        r"\bAER\b",
        r"NIC\s+Link",
        r"\bmcelog\b",
        r"IPMI",
        r"\bSEL\b",
        r"Corrected\s+error",
        r"Uncorrected",
        r"\bSTATUS\b",
        r"\bMCA:",
        r"Error\s+code",
        r"\bBank\b",
        r"DIMM",
        r"\bCPU\s+\d+",
    ]
]

# MCE 块起始 / 续行
_MCE_START = re.compile(
    r"Hardware\s+event|Hardware\s+Error|Machine\s+Check|\bmce:|^MCE\s",
    re.IGNORECASE,
)
# Bug1: 全部 IGNORECASE，兼容 IBM BANK / STATUS 等大写格式
_MCE_CONTINUE = re.compile(
    r"STATUS|MCGSTATUS|MCGCAP|CPUID|MCA:|Bank|Error\s+code|MISC|TIME|"
    r"Corrected\s+error|Uncorrected|SOCKETID|APICID|PROCESSOR|"
    r"^\s*CPU\s+\d+|^\s*MCE\s+\d+|BINIT|timeout",
    re.IGNORECASE,
)

_EDAC_START = re.compile(r"\bEDAC\b|MEMORY\s+CONTROLLER|DIMM\s+\d+", re.IGNORECASE)
_EDAC_CONTINUE = re.compile(
    r"EDAC|DIMM|Channel|CSROW|mc\d+|CE|UE|page:|offset:|grain:",
    re.IGNORECASE,
)

# Bug3: 词边界，避免 AERR 误命中 AER
_PCIE_START = re.compile(r"pcieport|\bAER\b|PCIe\s+Bus\s+Error", re.IGNORECASE)
_PCIE_CONTINUE = re.compile(
    r"pcieport|\bAER\b|severity|severity_status|device_status|Uncorrected|"
    r"Corrected|TLP|Receiver\s+Error|Bad\s+TLP",
    re.IGNORECASE,
)

_IPMI_SENSOR = re.compile(
    r"(?:Temperature|Temp|Fan|Voltage|PSU|Power\s+Supply).{0,40}"
    r"(?:critical|warning|failed|out\s+of\s+range|\d+\s*°?C|\d+\s*RPM)",
    re.IGNORECASE,
)
_SMART = re.compile(
    r"SMART|Disk|ata\d+|nvme\d+.*(fail|error|reallocated|UNC|temperature)",
    re.IGNORECASE,
)
_NIC = re.compile(
    r"NIC\s+Link|eth\d+.*(?:link\s+down|carrier)|ixgbe|i40e|mlx\d+.*error",
    re.IGNORECASE,
)

_RE_CPU = re.compile(r"CPU\s+(\d+)", re.IGNORECASE)
_RE_BANK = re.compile(r"BANK\s+(\d+)", re.IGNORECASE)
_RE_SOCKET = re.compile(r"SOCKETID\s+(\d+)", re.IGNORECASE)
# Bug2: STATUS / Error code 均可选 0x 前缀
_RE_ERROR_CODE = re.compile(r"Error\s+code\s+(?:0x)?([0-9a-fA-F]+)", re.IGNORECASE)
_RE_STATUS = re.compile(r"STATUS\s+(?:0x)?([0-9a-fA-F]+)", re.IGNORECASE)
_RE_ERR_DESC = re.compile(r"Error\s+code\s+\w+:\s*(.+)", re.IGNORECASE)
_RE_MCA_DESC = re.compile(r"MCA:\s*(.+)", re.IGNORECASE)
_RE_BINIT = re.compile(r"(timeout\s+BINIT.*)", re.IGNORECASE)


def _has_hardware_signal(line: str) -> bool:
    return any(p.search(line) for p in _HARDWARE_KEEP_PATTERNS)


def _is_noise_only(line: str) -> bool:
    if _has_hardware_signal(line):
        return False
    return any(p.search(line) for p in _NOISE_PATTERNS)


def denoise_log(log_text: str) -> tuple[str, list[str]]:
    """过滤非硬件噪音行；含硬件关键词的行一律保留。"""
    kept: list[str] = []
    dropped: list[str] = []
    for raw in (log_text or "").splitlines():
        line = raw.rstrip()
        if not line.strip():
            continue
        if _is_noise_only(line):
            dropped.append(line)
            continue
        # 无噪音词但也不像硬件行时：若整段几乎都是硬件上下文仍可能保留
        # MVP：无噪音则保留，避免误杀未收录格式
        kept.append(line)
    return "\n".join(kept), dropped


def _normalize_hex(code: str | None) -> str:
    if not code:
        return ""
    code = code.strip()
    if not code:
        return ""
    if code.lower().startswith("0x"):
        return "0x" + code[2:].lower()
    # 纯十六进制补 0x；短十进制报错码也按十六进制惯例补前缀
    if re.fullmatch(r"[0-9a-fA-F]+", code):
        return "0x" + code.lower()
    return code


def extract_mce_features(block_text: str) -> dict[str, str]:
    """从 MCE 块文本提取结构化特征（含 Bug1–4 修复）。"""
    location_parts: list[str] = []

    cpu_m = _RE_CPU.search(block_text)
    if cpu_m:
        location_parts.append(f"CPU {cpu_m.group(1)}")

    bank_m = _RE_BANK.search(block_text)
    if bank_m:
        location_parts.append(f"Bank {bank_m.group(1)}")

    if not location_parts:
        sock_m = _RE_SOCKET.search(block_text)
        if sock_m:
            location_parts.append(f"SOCKET {sock_m.group(1)}")

    location = " ".join(location_parts) if location_parts else "Unknown"

    error_code = ""
    code_m = _RE_ERROR_CODE.search(block_text)
    if code_m:
        error_code = _normalize_hex(code_m.group(1))
    else:
        status_m = _RE_STATUS.search(block_text)
        if status_m:
            error_code = _normalize_hex(status_m.group(1))

    error_description = ""
    desc_m = _RE_ERR_DESC.search(block_text)
    if desc_m:
        error_description = desc_m.group(1).strip()
    else:
        mca_m = _RE_MCA_DESC.search(block_text)
        if mca_m:
            error_description = mca_m.group(1).strip()
        else:
            binit_m = _RE_BINIT.search(block_text)
            if binit_m:
                error_description = binit_m.group(1).strip()

    # Bug4: Corrected 优先判定为 Warning
    severity = "Unknown"
    if re.search(r"\bCorrected\b", block_text, re.IGNORECASE):
        severity = "Warning"
    elif re.search(
        r"\bUncorrected\b|\bFatal\b|\bIERR\b|\bUE\b",
        block_text,
        re.IGNORECASE,
    ):
        severity = "Critical"
    elif error_description:
        severity = "Warning"

    return {
        "fault_type": "MCE",
        "component": "CPU",
        "location": location,
        "error_code": error_code,
        "error_description": error_description,
        "severity": severity,
        "vendor": "Generic",
    }


def extract_edac_features(block_text: str) -> dict[str, str]:
    location = "Unknown"
    ch = re.search(r"Channel\s*(\d+)", block_text, re.IGNORECASE)
    dimm = re.search(r"DIMM\s*(\d+)", block_text, re.IGNORECASE)
    parts = []
    if ch:
        parts.append(f"Channel {ch.group(1)}")
    if dimm:
        parts.append(f"DIMM {dimm.group(1)}")
    if parts:
        location = ", ".join(parts)

    if re.search(r"\bUE\b|Uncorrected", block_text, re.IGNORECASE):
        code, severity = "UE", "Critical"
    elif re.search(r"\bCE\b|Corrected", block_text, re.IGNORECASE):
        code, severity = "CE", "Warning"
    else:
        code, severity = "", "Unknown"

    desc_m = re.search(r"EDAC[^\n]*", block_text, re.IGNORECASE)
    desc = desc_m.group(0).strip() if desc_m else "EDAC memory error"

    return {
        "fault_type": "Memory",
        "component": "Memory",
        "location": location,
        "error_code": code,
        "error_description": desc,
        "severity": severity,
        "vendor": "Generic",
    }


def extract_pcie_features(block_text: str) -> dict[str, str]:
    loc_m = re.search(r"pcieport\s+([0-9a-fA-F:.]+)", block_text, re.IGNORECASE)
    location = loc_m.group(1) if loc_m else "Unknown"
    severity = (
        "Critical"
        if re.search(r"Uncorrected|Fatal", block_text, re.IGNORECASE)
        else "Warning"
    )
    desc_m = re.search(r"(PCIe\s+Bus\s+Error|[^\n]*\bAER\b[^\n]*)", block_text, re.IGNORECASE)
    desc = desc_m.group(1).strip() if desc_m else "PCIe AER error"
    return {
        "fault_type": "PCIe",
        "component": "PCIe",
        "location": location,
        "error_code": "AER",
        "error_description": desc,
        "severity": severity,
        "vendor": "Generic",
    }


def extract_ipmi_sensor(line: str) -> dict[str, str] | None:
    if not _IPMI_SENSOR.search(line):
        return None
    component = "Temperature"
    if re.search(r"\bFan\b", line, re.IGNORECASE):
        component = "Fan"
    elif re.search(r"Voltage|PSU|Power", line, re.IGNORECASE):
        component = "Voltage"

    code = ""
    m_temp = re.search(r"(\d+)\s*°?C", line, re.IGNORECASE)
    m_rpm = re.search(r"(\d+)\s*RPM", line, re.IGNORECASE)
    if m_temp:
        code = f"{m_temp.group(1)}°C"
    elif m_rpm:
        code = f"{m_rpm.group(1)} RPM"

    severity = (
        "Critical"
        if re.search(r"critical|failed", line, re.IGNORECASE)
        else "Warning"
    )
    return {
        "fault_type": "IPMI_Sensor",
        "component": component,
        "location": "Unknown",
        "error_code": code or "SENSOR",
        "error_description": line.strip(),
        "severity": severity,
        "vendor": "Generic",
    }


def extract_smart(line: str) -> dict[str, str] | None:
    if not _SMART.search(line):
        return None
    dev_m = re.search(r"(nvme\d+n\d+|sd[a-z]+|ata\d+)", line, re.IGNORECASE)
    location = dev_m.group(1) if dev_m else "Unknown"
    severity = (
        "Critical"
        if re.search(r"fail|UNC|error", line, re.IGNORECASE)
        else "Warning"
    )
    return {
        "fault_type": "SMART",
        "component": "Disk",
        "location": location,
        "error_code": "SMART",
        "error_description": line.strip(),
        "severity": severity,
        "vendor": "Generic",
    }


def extract_nic(line: str) -> dict[str, str] | None:
    if not _NIC.search(line):
        return None
    iface_m = re.search(r"(eth\d+|ens\d+\w*|enp\S+)", line, re.IGNORECASE)
    location = iface_m.group(1) if iface_m else "Unknown"
    return {
        "fault_type": "Network",
        "component": "NIC",
        "location": location,
        "error_code": "LINK",
        "error_description": line.strip(),
        "severity": "Warning",
        "vendor": "Generic",
    }


def _is_pure_mce(cleaned: str) -> bool:
    """降噪后是否仅含 MCE（无 EDAC / IPMI / SMART / PCIe / 网卡）。"""
    if not cleaned.strip():
        return False
    has_mce = bool(
        re.search(r"MCE|Machine\s+Check|Hardware\s+event|Hardware\s+Error|mce:", cleaned, re.I)
    )
    if not has_mce:
        return False
    has_other = bool(
        re.search(r"\bEDAC\b", cleaned, re.I)
        or _IPMI_SENSOR.search(cleaned)
        or _SMART.search(cleaned)
        or _PCIE_START.search(cleaned)
        or _NIC.search(cleaned)
    )
    return not has_other


def _flush_block(
    kind: str,
    lines: list[str],
    faults: list[dict[str, str]],
) -> None:
    if not lines:
        return
    text = "\n".join(lines)
    if kind == "mce":
        faults.append(extract_mce_features(text))
    elif kind == "edac":
        faults.append(extract_edac_features(text))
    elif kind == "pcie":
        faults.append(extract_pcie_features(text))


def scan_faults(cleaned_log: str) -> tuple[list[dict[str, str]], list[str]]:
    """多故障状态机：逐行扫描，返回 faults 与未识别行。"""
    faults: list[dict[str, str]] = []
    unmatched: list[str] = []

    if _is_pure_mce(cleaned_log):
        # 快速通道：整段作为 MCE 输入
        faults.append(extract_mce_features(cleaned_log))
        return faults, unmatched

    in_mce = in_edac = in_pcie = False
    block: list[str] = []
    kind = ""

    def _close() -> None:
        nonlocal in_mce, in_edac, in_pcie, block, kind
        if kind and block:
            _flush_block(kind, block, faults)
        in_mce = in_edac = in_pcie = False
        block = []
        kind = ""

    for line in cleaned_log.splitlines():
        # ---- 块内续行 ----
        if in_mce:
            if _MCE_CONTINUE.search(line) or _MCE_START.search(line):
                block.append(line)
                continue
            _close()
        elif in_edac:
            if _EDAC_CONTINUE.search(line) or _EDAC_START.search(line):
                block.append(line)
                continue
            _close()
        elif in_pcie:
            if _PCIE_CONTINUE.search(line) or _PCIE_START.search(line):
                block.append(line)
                continue
            _close()

        # ---- 新块起始 ----
        if _MCE_START.search(line):
            in_mce, kind = True, "mce"
            block = [line]
            continue
        if _EDAC_START.search(line):
            in_edac, kind = True, "edac"
            block = [line]
            continue
        if _PCIE_START.search(line):
            in_pcie, kind = True, "pcie"
            block = [line]
            continue

        # ---- 单行故障 ----
        hit = extract_ipmi_sensor(line) or extract_smart(line) or extract_nic(line)
        if hit:
            faults.append(hit)
        else:
            # 可能仍是 MCE 续行漏检（保守：含 CPU/BANK/STATUS 计入）
            if re.search(r"STATUS|BANK|MCA:|Error\s+code", line, re.I):
                # 孤儿 MCE 线索：单独提一次
                faults.append(extract_mce_features(line))
            else:
                unmatched.append(line)

    _close()
    return faults, unmatched


def _core_fields_missing(fault: dict[str, str]) -> bool:
    return not fault.get("error_code") or not fault.get("error_description")


def build_rag_query(faults: list[dict[str, str]], cleaned_log: str) -> str:
    """构造 RAG 查询词；MCE 使用增强查询便于命中 Intel MCE 错误码表。"""
    if not faults:
        return (cleaned_log or "")[:200].strip() or "hardware fault diagnosis"

    primary = faults[0]
    ftype = primary.get("fault_type", "")
    code = primary.get("error_code", "")
    component = primary.get("component", "")
    desc = primary.get("error_description", "")

    if ftype == "MCE":
        # 增强查询：帮助检索 Intel MCE 错误码对照表
        parts = ["MCE", code, component, "Intel Machine Check Error code"]
        if desc:
            parts.append(desc[:80])
        query = " ".join(p for p in parts if p).strip()
    else:
        query = " ".join(
            p for p in [ftype, component, code, desc[:80], primary.get("location", "")] if p
        ).strip()

    return query or (cleaned_log or "")[:200].strip() or "hardware fault diagnosis"


def build_llm_context(cleaned_log: str, faults: list[dict[str, str]]) -> str:
    features = json.dumps(faults, ensure_ascii=False, indent=2)
    return (
        "【降噪后的硬件日志】\n"
        f"{cleaned_log}\n\n"
        "【正则提取的故障特征】\n"
        f"{features}"
    )


# Dify 代码节点已声明的全部输出变量（须全部返回且均为 String，变量名 ≤30）
_OUTPUT_DEFAULTS: dict[str, str] = {
    "fault_type": "Unknown",
    "component": "Unknown",
    "location": "Unknown",
    "error_code": "",
    "error_description": "",
    "severity": "Unknown",
    "vendor": "Generic",
    "features_json": "[]",
    "fault_count": "0",
    "faults": "[]",
    "cleaned_log": "",
    "rag_query": "hardware fault diagnosis",
    "llm_context": "",
    "llm_fallback_text": "",
    "llm_fallback_needed": "false",
}


def _as_str(value: Any, default: str = "") -> str:
    """将任意返回值规范为 Dify String（禁止 None / 非标量）。"""
    if value is None:
        return default
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (dict, list)):
        return json.dumps(value, ensure_ascii=False)
    return str(value)


def validate_outputs(result: dict[str, Any]) -> dict[str, str]:
    """校验并补齐全部输出参数，保证 Dify 输出参数校验通过。

    - 缺键 → 用默认值补齐
    - 多余键 → 丢弃（避免未声明参数触发校验失败）
    - 所有值 → 强制转为非空合法 String（允许空字符串字段）
    """
    validated: dict[str, str] = {}
    for key, default in _OUTPUT_DEFAULTS.items():
        validated[key] = _as_str(result.get(key, default), default)

    # rag_query / llm_context 下游强依赖，禁止最终仍为空
    if not validated["rag_query"].strip():
        fallback_src = validated["cleaned_log"] or validated["error_description"] or "hardware fault diagnosis"
        validated["rag_query"] = fallback_src[:200]
    if not validated["llm_context"].strip():
        validated["llm_context"] = build_llm_context(
            validated["cleaned_log"],
            [],
        )

    # llm_fallback_needed 只允许 true/false
    flag = validated["llm_fallback_needed"].strip().lower()
    validated["llm_fallback_needed"] = "true" if flag in {"true", "1", "yes"} else "false"

    # 二次确认：声明的每个输出参数都已存在且为 str
    missing = [k for k in _OUTPUT_DEFAULTS if k not in validated]
    bad_type = [k for k, v in validated.items() if not isinstance(v, str)]
    if missing or bad_type:
        raise ValueError(
            f"Output parameter validation failed: missing={missing}, bad_type={bad_type}"
        )
    return validated


def main(log_text: str, server_id: str = "") -> dict:
    """
    Dify 代码节点入口。

    Returns:
        下游节点所需的全部字段（全部为 String，且与输出变量一一对应）。
    """
    _ = server_id  # MVP 未强制使用，保留签名兼容工作流

    cleaned_log, _dropped = denoise_log(log_text or "")
    faults, unmatched = scan_faults(cleaned_log) if cleaned_log else ([], [])

    # 降级判断
    llm_fallback_needed = "false"
    if not faults:
        llm_fallback_needed = "true"
    elif any(_core_fields_missing(f) for f in faults):
        llm_fallback_needed = "true"

    # 主故障（取首个；无则填 Unknown 占位，保证字段齐全）
    if faults:
        primary: dict[str, str] = faults[0]
    else:
        primary = {
            "fault_type": "Unknown",
            "component": "Unknown",
            "location": "Unknown",
            "error_code": "",
            "error_description": "",
            "severity": "Unknown",
            "vendor": "Generic",
        }

    faults_json = json.dumps(faults, ensure_ascii=False)
    rag_query = build_rag_query(faults, cleaned_log)
    llm_context = build_llm_context(cleaned_log, faults)
    llm_fallback_text = "\n".join(unmatched) if llm_fallback_needed == "true" else ""
    if llm_fallback_needed == "true" and not llm_fallback_text:
        llm_fallback_text = cleaned_log

    raw = {
        "fault_type": primary.get("fault_type", "Unknown"),
        "component": primary.get("component", "Unknown"),
        "location": primary.get("location", "Unknown"),
        "error_code": primary.get("error_code", ""),
        "error_description": primary.get("error_description", ""),
        "severity": primary.get("severity", "Unknown"),
        "vendor": primary.get("vendor", "Generic"),
        "features_json": faults_json,
        "fault_count": str(len(faults)),
        "faults": faults_json,
        "cleaned_log": cleaned_log,
        "rag_query": rag_query,
        "llm_context": llm_context,
        "llm_fallback_text": llm_fallback_text,
        "llm_fallback_needed": llm_fallback_needed,
    }
    return validate_outputs(raw)


# ---------------------------------------------------------------------------
# 本地快速自检（Dify 中不会执行）
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    samples = [
        (
            "std_mce",
            """CPU 0: Machine Check Exception: 0000000000000004
Bank 4: f200000000070005
Error code 0x0005: Internal parity error
""",
        ),
        (
            "ibm_mce",
            """Hardware event. This is not a software error.
MCE 0
CPU 16 BANK 0
Corrected error
STATUS d8001dc000020e0f MCGSTATUS 0
MCA: BUS Level-3 Generic Generic Other-transaction Request-did-not-timeout Error
""",
        ),
    ]
    required = set(_OUTPUT_DEFAULTS)
    for name, text in samples:
        out = main(text, "srv-demo")
        assert set(out.keys()) == required, f"{name}: keys mismatch {set(out.keys()) ^ required}"
        assert all(isinstance(v, str) for v in out.values()), f"{name}: non-str values"
        print("=" * 60, name)
        print("keys_ok:", sorted(out.keys()))
        print("error_code:", out["error_code"])
        print("location:", out["location"])
        print("severity:", out["severity"])
        print("rag_query:", out["rag_query"])
        print("llm_fallback_needed:", out["llm_fallback_needed"])
        print("faults:", out["faults"])
