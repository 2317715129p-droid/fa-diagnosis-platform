"""Dify workflow API client with SSE streaming for FA diagnosis.

Fix note: Dify requires body field \"user\"; without it the API returns HTTP 400
JSON (\"Arg user must be provided\") and yields 0 text chunks. Also harden SSE
parsing (messages separated by blank lines / \\n\\n) and surface non-200 errors.
"""

from __future__ import annotations

import json
from collections.abc import AsyncIterator
from typing import Any

import httpx

from config import DIFY_API_KEY, DIFY_API_URL, DIFY_TRANSLATE_API_KEY

MOCK_REPORT = [
    "### 【故障现象定位】\n",
    "- 故障部件：**CPU**\n",
    "- 物理位置：**CPU 0 Bank 4**\n",
    "- 报错代码：0x0005\n",
    "- 故障等级：严重\n",
    "\n",
    "### 【物理根因推导】\n",
    "判断为 CPU 内部缓存奇偶校验错误。[依据：Intel_MCE错误码对照表.md]\n",
    "\n",
    "### 【工程处置建议】\n",
    "1. 紧急处置：立即将该服务器从业务集群摘除\n",
    "2. 根治方案：更换 CPU 0 备件\n",
    "3. 验证方法：更换后运行 stress-ng 压力测试\n",
    "\n",
    "### 【置信度评估】\n",
    "- 诊断置信度：高\n",
]


def _extract_data_payload(line: str) -> str | None:
    """Return JSON payload from an SSE data line, or None if not a data line."""
    if line.startswith("data: "):
        return line[6:].strip()
    if line.startswith("data:"):
        return line[5:].strip()
    return None


def _text_from_outputs(outputs: Any) -> str | None:
    """Best-effort extract final report text from workflow_finished outputs."""
    if outputs is None:
        return None
    if isinstance(outputs, str) and outputs.strip():
        return outputs
    if not isinstance(outputs, dict):
        return None
    for key in ("report_en", "result", "text", "output", "report", "answer"):
        value = outputs.get(key)
        if isinstance(value, str) and value.strip():
            return value
    for value in outputs.values():
        if isinstance(value, str) and value.strip():
            return value
    return None


async def translate_report(report_zh: str) -> str:
    """Translate a Chinese FA report to English via Dify blocking workflow.

    Uses DIFY_TRANSLATE_API_KEY. Raises ValueError/RuntimeError on failure.
    """
    text = (report_zh or "").strip()
    if not text:
        raise ValueError("report_zh is empty")

    if not DIFY_TRANSLATE_API_KEY:
        raise RuntimeError("DIFY_TRANSLATE_API_KEY is not configured")

    url = f"{DIFY_API_URL.rstrip('/')}/v1/workflows/run"
    headers = {
        "Authorization": f"Bearer {DIFY_TRANSLATE_API_KEY}",
        "Content-Type": "application/json",
    }
    body: dict[str, Any] = {
        "inputs": {"report_zh": text},
        "response_mode": "blocking",
        "user": "admin",
    }

    try:
        async with httpx.AsyncClient(timeout=2000.0) as client:
            response = await client.post(url, json=body, headers=headers)
    except httpx.HTTPError as exc:
        raise RuntimeError(f"Dify translate request failed: {exc}") from exc

    if response.status_code != 200:
        raise RuntimeError(
            f"Dify translate HTTP {response.status_code}: {response.text[:500]}"
        )

    try:
        payload = response.json()
    except json.JSONDecodeError as exc:
        raise RuntimeError("Dify translate returned invalid JSON") from exc

    # Blocking mode: { data: { outputs: { report_en: "..." }, status: "succeeded" } }
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, dict):
        data = payload if isinstance(payload, dict) else {}

    if data.get("status") == "failed":
        raise RuntimeError(f"Dify translate failed: {data.get('error')}")

    outputs = data.get("outputs")
    if outputs is None and isinstance(payload, dict):
        outputs = payload.get("outputs")

    report_en = None
    if isinstance(outputs, dict):
        report_en = outputs.get("report_en")
        if not (isinstance(report_en, str) and report_en.strip()):
            report_en = _text_from_outputs(outputs)
    elif isinstance(outputs, str):
        report_en = outputs

    if not (isinstance(report_en, str) and report_en.strip()):
        raise RuntimeError("Dify translate returned empty report_en")

    return report_en.strip()


async def run_dify_workflow(log_text: str, server_id: str) -> AsyncIterator[str]:
    """Calls the Dify workflow API with SSE streaming.

    Yields text chunks one by one as they arrive.
    Falls back to mock data if API key is not configured.
    """
    if not DIFY_API_KEY:
        for chunk in MOCK_REPORT:
            yield chunk
        return

    url = f"{DIFY_API_URL.rstrip('/')}/v1/workflows/run"
    headers = {
        "Authorization": f"Bearer {DIFY_API_KEY}",
        "Content-Type": "application/json",
        "Accept": "text/event-stream",
    }
    # Dify requires \"user\"; omitting it causes HTTP 400 and zero chunks.
    body: dict[str, Any] = {
        "inputs": {
            "log_text": log_text,
            "server_id": server_id,
        },
        "response_mode": "streaming",
        "user": "admin",
    }

    chunk_count = 0
    finished_outputs: Any = None

    try:
        # Connect timeout short so UI fails fast when Dify is down locally
        # Read timeout 2000s for slow LLM inference; connect 30s for fast fail
        timeout = httpx.Timeout(2000.0, connect=30.0)
        async with httpx.AsyncClient(timeout=timeout) as client:
            async with client.stream("POST", url, json=body, headers=headers) as response:
                if response.status_code != 200:
                    error_body = (await response.aread()).decode("utf-8", errors="replace")
                    raise RuntimeError(
                        f"Dify HTTP {response.status_code}: {error_body[:300]}"
                    )

                buffer = ""
                async for raw in response.aiter_text():
                    buffer += raw
                    # SSE messages are separated by a blank line (\n\n).
                    while "\n\n" in buffer:
                        message, buffer = buffer.split("\n\n", 1)
                        for line in message.splitlines():
                            line = line.strip()
                            if not line:
                                continue
                            payload = _extract_data_payload(line)
                            if payload is None:
                                continue
                            if payload in ("[DONE]", "DONE"):
                                continue
                            try:
                                event_data = json.loads(payload)
                            except json.JSONDecodeError:
                                continue

                            event = event_data.get("event")
                            data = event_data.get("data") or {}

                            if event == "text_chunk":
                                text = data.get("text")
                                if text:
                                    chunk_count += 1
                                    yield text
                            elif event == "workflow_finished":
                                finished_outputs = data.get("outputs")
                                if data.get("status") == "failed":
                                    raise RuntimeError(
                                        f"Dify workflow failed: {data.get('error')}"
                                    )

                # Flush any trailing buffered message without a final \n\n.
                if buffer.strip():
                    for line in buffer.splitlines():
                        line = line.strip()
                        payload = _extract_data_payload(line)
                        if not payload:
                            continue
                        try:
                            event_data = json.loads(payload)
                        except json.JSONDecodeError:
                            continue
                        if event_data.get("event") == "text_chunk":
                            text = (event_data.get("data") or {}).get("text")
                            if text:
                                chunk_count += 1
                                yield text
                        elif event_data.get("event") == "workflow_finished":
                            finished_outputs = (event_data.get("data") or {}).get("outputs")

        # Fallback: some workflows only return final text in workflow_finished.
        if chunk_count == 0:
            fallback = _text_from_outputs(finished_outputs)
            if fallback:
                print("No text_chunk events; falling back to workflow_finished outputs")
                yield fallback
            else:
                raise RuntimeError(
                    "Dify returned 0 text chunks. Check workflow output / API key."
                )

    except httpx.HTTPError as exc:
        raise RuntimeError(
            f"无法连接 Dify（{DIFY_API_URL}）: {exc}. "
            "请确认本机 Dify 已启动（通常 http://localhost），或暂时清空 .env 里的 DIFY_API_KEY 使用模拟报告。"
        ) from exc
    except RuntimeError:
        raise
    except Exception as exc:
        raise RuntimeError(f"Dify unexpected error: {exc}") from exc